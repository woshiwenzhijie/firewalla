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

const log = require('../net2/logger.js')(__filename);

const Sensor = require('./Sensor.js').Sensor;

const async = require('asyncawait/async');
const await = require('asyncawait/await');

const sem = require('../sensor/SensorEventManager.js').getInstance();

const SSDPClient = require('node-ssdp').Client

const request = require('request')

const parseString = require('xml2js').parseString;

const l2 = require('../util/Layer2.js');

const URL = require('url').URL;
const SM = require('../net2/SysManager.js');
const sm = new SM();

class SSDPSensor extends Sensor {

  onResponse(headers, statusCode, rinfo) {
    // only support ipv4 yet
    if(rinfo.family === 'IPv4' && statusCode === 200) {
      let ip = rinfo.address;
      let location = headers.LOCATION;

      try {
        let url = new URL(location);

        if (!sm.inMySubnets4(url.hostname)) {
          log.warn(`SSDP Location outside of v4 subnets: ${location} via ${ip}:${rinfo.port}`);
          this.locationCache[ip] = 0;
          return;
        }
      } catch(e) {
        log.error("Invalid SSDP location", headers, statusCode, rinfo);
        return;
      }


      let lastFoundTimestamp = this.locationCache[ip];
      if(!lastFoundTimestamp || lastFoundTimestamp < new Date() / 1000 - this.CACHE_INTERVAL) {
        this.locationCache[ip] = new Date() / 1000;
        this.parseURL(ip, location, (err) => {
          if(err) {
            this.locationCache[ip] = 0;
          }
        })
      }
    } else if (statusCode !== 200) {
      log.debug("Got an error ssdp response: ", headers, statusCode, rinfo)
    } else {
      log.warn("Unsupported ssdp response: ", headers, statusCode, rinfo)
    }
  }

  notify(ip, ssdpResult) {
    l2.getMAC(ip, (err, mac) => {
      
      if(err) {
        // not found, ignore this host
        log.error("Not able to found mac address for host:", ip, mac);
        return;
      }

      let host = {
        ipv4: ip,
        ipv4Addr: ip,
        mac: mac,
        bname: ssdpResult.deviceName,
        modelName: ssdpResult.modelName,
        manufacturer: ssdpResult.manufacturer,
        from: "ssdp"
      }

      log.info(`Found a device via ssdp: ${host.bname} (${ip} - ${host.mac})`)
      
      sem.emitEvent({
        type: "DeviceUpdate",
        message: `Found a device via ssdp ${ip} ${mac}`,
        host: host
      })
      
    });
  }
  
  parseURL(ip, location, callback) {
    let options = {
      uri: location,
      method: 'GET'
    }
    request(options, (err, response, body) => {
      if(err) {
        log.error("Failed to GET", location, "err:", err)
        callback(err)
        return
      }

      parseString(body, (err, result) => {
        if(err) {
          log.error(`Invalid SSDP XML for location ${location}, err: ${err}`)
          callback(err)
          return
        }

        const rr = this.parseContent(result)

        if(rr && rr.deviceName) {
          this.notify(ip, rr)
        }

        callback(null)
      })
    });
  }

  getElement(object, element) {
    let array = object[element]

    return array && (array.constructor.name === 'Array') && array.length > 0 && array[0]
  }
  
  parseContent(content) {
    let root = content && content.root

    if(!root) {
      return
    }

    let firstDevice = this.getElement(root, "device")

    if(!firstDevice)
      return

    let deviceName = this.getElement(firstDevice, "friendlyName")

    let manufacturer = this.getElement(firstDevice, "manufacturer")

    let modelName = this.getElement(firstDevice, "modelName")

    return {
      deviceName: deviceName,
      manufacturer: manufacturer,
      modelName: modelName
    }
  }
  
  run() {
    this.ssdpClient = new SSDPClient();
    this.locationCache = {};
    this.CACHE_INTERVAL = this.config.cacheTTL || 3600; // one hour
    this.ssdpClient.on('response', (header, statusCode, rinfo) => {
      this.onResponse(header, statusCode, rinfo)
    });
    process.nextTick(() => {
      this.ssdpClient.search('ssdp:all')
    })

    setInterval(() => {
      this.ssdpClient.search('ssdp:all')
    }, this.config.interval * 1000 || 10 * 60 * 1000) // every 10 minutes
  }
}


module.exports = SSDPSensor
