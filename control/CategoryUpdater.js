/*    Copyright 2016 Firewalla LLC
 *
 *    This program is free software: you can redistribute it and/or  modify
 *    it under the terms of the GNU Affero General Public License, version 3,
 *    as published by the Free Software Foundation.
 *
 *    This program is distributed in the hope that it will be useful,
 *    but WITHOUT ANY WARRANTY; without even the implied warranty of
 *    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *    GNU Affero General Public License for more details.
 *
 *    You should have received a copy of the GNU Affero General Public License
 *    along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
'use strict';

const log = require("../net2/logger.js")(__filename);

const rclient = require('../util/redis_manager.js').getRedisClient()

const firewalla = require("../net2/Firewalla.js");

const DNSTool = require('../net2/DNSTool.js')
const dnsTool = new DNSTool()

const CategoryUpdaterBase = require('./CategoryUpdaterBase.js');
const domainBlock = require('../control/DomainBlock.js')();

const exec = require('child-process-promise').exec

const sem = require('../sensor/SensorEventManager.js').getInstance();

const _ = require('lodash');

let instance = null

const EXPIRE_TIME = 60 * 60 * 48 // one hour

class CategoryUpdater extends CategoryUpdaterBase {

  constructor() {
    if (instance == null) {
      super()
      this.inited = false;
      instance = this

      this.activeCategories = {
        "games": 1,
        "social": 1,
        "porn": 1,
        "shopping": 1,
        "av": 1,
        "default_c": 1,
        "p2p": 1,
        "gamble": 1
      };

      this.excludedDomains = {
        "av": [
          "www.google.com",
          "forcesafesearch.google.com",
          "docs.google.com",
          "*.itunes.apple.com",
          "itunes.apple.com"
        ]
      };

      // only run refresh category records for fire main process
      sem.once('IPTABLES_READY', async () => {
        this.inited = true;
        if (firewalla.isMain()) {
          setInterval(() => {
            this.refreshAllCategoryRecords()
          }, 60 * 60 * 1000) // update records every hour

          await this.refreshAllCategoryRecords()

          sem.on('UPDATE_CATEGORY_DYNAMIC_DOMAIN', (event) => {
            if(event.category) {
              this.recycleIPSet(event.category)
            }
          });
        }
      })
    }

    return instance
  }

  async getDomains(category) {
    if(!this.isActivated(category))
      return []

    return rclient.zrangeAsync(this.getCategoryKey(category), 0, -1)
  }

  async getDefaultDomains(category) {
    if(!this.isActivated(category))
      return []

    return rclient.smembersAsync(this.getDefaultCategoryKey(category))
  }

  async addDefaultDomains(category, domains) {
    if(!this.isActivated(category))
      return []

    if(domains.length === 0) {
      return []
    }

    let commands = [this.getDefaultCategoryKey(category)]

    commands.push.apply(commands, domains)
    return rclient.saddAsync(commands)
  }

  async flushDefaultDomains(category) {
    if(!this.isActivated(category))
      return [];

    return rclient.delAsync(this.getDefaultCategoryKey(category));
  }

  async getIncludedDomains(category) {
    if(!this.isActivated(category))
      return []

    return rclient.smembersAsync(this.getIncludeCategoryKey(category))
  }

  async addIncludedDomain(category, domain) {
    if(!this.isActivated(category))
      return

    return rclient.saddAsync(this.getIncludeCategoryKey(category), domain)
  }

  async removeIncludedDomain(category, domain) {
    if(!this.isActivated(category))
      return

    return rclient.sremAsync(this.getIncludeCategoryKey(category), domain)
  }

  async getExcludedDomains(category) {
    if(!this.isActivated(category))
      return []

    return rclient.smembersAsync(this.getExcludeCategoryKey(category))
  }

  async addExcludedDomain(category, domain) {
    if(!this.isActivated(category))
      return

    return rclient.saddAsync(this.getExcludeCategoryKey(category), domain)
  }

  async removeExcludedDomain(category, domain) {
    if(!this.isActivated(category))
      return

    return rclient.sremAsync(this.getExcludeCategoryKey(category), domain)
  }

  async includeDomainExists(category, domain) {
    if(!this.isActivated(category))
      return false

    return rclient.sismemberAsync(this.getIncludeCategoryKey(category), domain)
  }

  async excludeDomainExists(category, domain) {
    if(!this.isActivated(category))
      return false

    return rclient.sismemberAsync(this.getExcludeCategoryKey(category), domain)
  }

  async getDomainsWithExpireTime(category) {
    const key = this.getCategoryKey(category)

    const domainAndScores = await rclient.zrevrangebyscoreAsync(key, '+inf', 0, 'withscores')
    const results = []

    for(let i = 0; i < domainAndScores.length; i++) {
      if(i % 2 === 1) {
        const domain = domainAndScores[i-1]
        const score = Number(domainAndScores[i])
        const expireDate = score + EXPIRE_TIME

        results.push({domain: domain, expire: expireDate})
      }
    }

    return results
  }

  async updateDomain(category, domain, isPattern) {

    if(!category || !domain) {
      return;
    }

    if(!this.isActivated(category)) {
      return
    }

    const now = Math.floor(new Date() / 1000)
    const key = this.getCategoryKey(category)

    let d = domain
    if(isPattern) {
      d = `*.${domain}`
    }

    const included = await this.includeDomainExists(category, d);

    if(!included) {
      const excluded = await this.excludeDomainExists(category, d);

      if(excluded) {
        return;
      }
    }

    log.debug(`Found a ${category} domain: ${d}`)

    await rclient.zaddAsync(key, now, d) // use current time as score for zset, it will be used to know when it should be expired out
    await this.updateIPSetByDomain(category, d)
    await this.filterIPSetByDomain(category);
  }

  getDomainMapping(domain) {
    return `rdns:domain:${domain}`
  }

  async getDomainMappingsByDomainPattern(domainPattern) {
    const keys = await rclient.keysAsync(this.getDomainMapping(domainPattern))
    keys.push(this.getDomainMapping(domainPattern.substring(2)))
    return keys
  }

  getSummedDomainMapping(domain) {
    let d = domain
    if(d.startsWith("*.")) {
      d = d.substring(2)
    }

    return `srdns:pattern:${d}`
  }

  // use "ipset restore" to add rdns entries to corresponding ipset
  async updateIPSetByDomain(category, domain, options) {
    if (!this.inited) return
    log.debug(`About to update category ${category} with domain ${domain}, options: ${JSON.stringify(options)}`)

    const mapping = this.getDomainMapping(domain)
    let ipsetName = this.getIPSetName(category)
    let ipset6Name = this.getIPSetNameForIPV6(category)

    if(options && options.useTemp) {
      ipsetName = this.getTempIPSetName(category)
      ipset6Name = this.getTempIPSetNameForIPV6(category)
    }

    if(domain.startsWith("*.")) {
      return this.updateIPSetByDomainPattern(category, domain, options)
    }

    const hasAny = await rclient.zcountAsync(mapping, '-inf', '+inf')

    if(hasAny) {
      let cmd4 = `redis-cli zrange ${mapping} 0 -1 | egrep -v ".*:.*" | sed 's=^=add ${ipsetName} = ' | sudo ipset restore -!`
      let cmd6 = `redis-cli zrange ${mapping} 0 -1 | egrep ".*:.*" | sed 's=^=add ${ipset6Name} = ' | sudo ipset restore -!`
      await exec(cmd4).catch((err) => {
        log.error(`Failed to update ipset by category ${category} domain ${domain}, err: ${err}`)
      })
      await exec(cmd6).catch((err) => {
        log.error(`Failed to update ipset6 by category ${category} domain ${domain}, err: ${err}`)
      })
    }

  }

  async filterIPSetByDomain(category, options) {
    if (!this.inited) return

    options = options || {}

    const list = this.excludedDomains && this.excludedDomains[category];

    if(!_.isEmpty(list)) {
      for(const domain of list) {
        if(domain.startsWith("*.")) {
          await this._filterIPSetByDomainPattern(category, domain, options).catch((err) => {
            log.error("Got error when filter ip set for domain pattern", domain, "with err", err);
          });
        } else {
          await this._filterIPSetByDomain(category, domain, options).catch((err) => {
            log.error("Got error when filter ip set for domain", domain, "with err", err);
          })
        }
      }
    }
  }

  async _filterIPSetByDomain(category, domain, options) {
    options = options || {}

    const mapping = this.getDomainMapping(domain)
    let ipsetName = this.getIPSetName(category)
    let ipset6Name = this.getIPSetNameForIPV6(category)

    if(options && options.useTemp) {
      ipsetName = this.getTempIPSetName(category)
      ipset6Name = this.getTempIPSetNameForIPV6(category)
    }

    const hasAny = await rclient.zcountAsync(mapping, '-inf', '+inf')

    if(hasAny) {
      let cmd4 = `redis-cli zrange ${mapping} 0 -1 | egrep -v ".*:.*" | sed 's=^=del ${ipsetName} = ' | sudo ipset restore -!`
      let cmd6 = `redis-cli zrange ${mapping} 0 -1 | egrep ".*:.*" | sed 's=^=del ${ipset6Name} = ' | sudo ipset restore -!`
      await exec(cmd4).catch((err) => {
        log.error(`Failed to delete ipset by category ${category} domain ${domain}, err: ${err}`)
      })
      await exec(cmd6).catch((err) => {
        log.error(`Failed to delete ipset6 by category ${category} domain ${domain}, err: ${err}`)
      })
    }
  }

  async _filterIPSetByDomainPattern(category, domain, options) {
    if(!domain.startsWith("*.")) {
      return
    }

    const mappings = await this.getDomainMappingsByDomainPattern(domain)

    if(mappings.length > 0) {
      const smappings = this.getSummedDomainMapping(domain)
      let array = [smappings, mappings.length]

      array.push.apply(array, mappings)

      await rclient.zunionstoreAsync(array)

      const exists = await rclient.typeAsync(smappings);
      if(exists === "none") {
        return; // if smapping doesn't exist, meaning no ip found for this domain, sometimes true for pre-provided domain list
      }

      await rclient.expireAsync(smappings, 600) // auto expire in 10 minutes

      let ipsetName = this.getIPSetName(category)
      let ipset6Name = this.getIPSetNameForIPV6(category)

      if(options && options.useTemp) {
        ipsetName = this.getTempIPSetName(category)
        ipset6Name = this.getTempIPSetNameForIPV6(category)
      }

      let cmd4 = `redis-cli zrange ${smappings} 0 -1 | egrep -v ".*:.*" | sed 's=^=del ${ipsetName} = ' | sudo ipset restore -!`
      let cmd6 = `redis-cli zrange ${smappings} 0 -1 | egrep ".*:.*" | sed 's=^=del ${ipset6Name} = ' | sudo ipset restore -!`
      return (async () => {
        await exec(cmd4);
        await exec(cmd6);
      })().catch((err) => {
        log.error(`Failed to filter ipset by category ${category} domain pattern ${domain}, err: ${err}`)
      })
    }
  }

  async updateIPSetByDomainPattern(category, domain, options) {
    if(!domain.startsWith("*.")) {
      return
    }

    log.debug(`About to update category ${category} with domain pattern ${domain}, options: ${JSON.stringify(options)}`)

    const mappings = await this.getDomainMappingsByDomainPattern(domain)

    if(mappings.length > 0) {
      const smappings = this.getSummedDomainMapping(domain)
      let array = [smappings, mappings.length]

      array.push.apply(array, mappings)

      await rclient.zunionstoreAsync(array)

      const exists = await rclient.typeAsync(smappings);
      if(exists === "none") {
        return; // if smapping doesn't exist, meaning no ip found for this domain, sometimes true for pre-provided domain list
      }

      await rclient.expireAsync(smappings, 600) // auto expire in 10 minutes

      let ipsetName = this.getIPSetName(category)
      let ipset6Name = this.getIPSetNameForIPV6(category)

      if(options && options.useTemp) {
        ipsetName = this.getTempIPSetName(category)
        ipset6Name = this.getTempIPSetNameForIPV6(category)
      }

      let cmd4 = `redis-cli zrange ${smappings} 0 -1 | egrep -v ".*:.*" | sed 's=^=add ${ipsetName} = ' | sudo ipset restore -!`
      let cmd6 = `redis-cli zrange ${smappings} 0 -1 | egrep ".*:.*" | sed 's=^=add ${ipset6Name} = ' | sudo ipset restore -!`
      try {
        await exec(cmd4)
        await exec(cmd6)
      } catch(err) {
        log.error(`Failed to update ipset by category ${category} domain pattern ${domain}, err: ${err}`)
      }
    }
  }

  // rebuild category ipset
  async recycleIPSet(category) {

    await this.updatePersistentIPSets(category, {useTemp: true});

    const domains = await this.getDomains(category)
    const includedDomains = await this.getIncludedDomains(category);
    const defaultDomains = await this.getDefaultDomains(category);
    const excludeDomains = await this.getExcludedDomains(category);

    let dd = _.union(domains, defaultDomains)
    dd = _.difference(dd, excludeDomains)
    dd = _.union(dd, includedDomains)

    for (const domain of dd) {

      let domainSuffix = domain
      if(domainSuffix.startsWith("*.")) {
        domainSuffix = domainSuffix.substring(2);
      }

      const existing = await dnsTool.reverseDNSKeyExists(domainSuffix)
      if(!existing) { // a new domain
        log.info(`Found a new domain with new rdns: ${domainSuffix}`)
        await domainBlock.resolveDomain(domainSuffix)
      }

      await this.updateIPSetByDomain(category, domain, {useTemp: true}).catch((err) => {
        log.error(`Failed to update ipset for domain ${domain}, err: ${err}`)
      })

      await this.filterIPSetByDomain(category, {useTemp: true}).catch((err) => {
        log.error(`Failed to filter ipset for domain ${domain}, err: ${err}`)
      })
    }

    await this.swapIpset(category);

    log.info(`Successfully recycled ipset for category ${category}`)
  }

  async refreshCategoryRecord(category) {
    const key = this.getCategoryKey(category)
    const date = Math.floor(new Date() / 1000) - EXPIRE_TIME

    return rclient.zremrangebyscoreAsync(key, '-inf', date)
  }
}

module.exports = CategoryUpdater
