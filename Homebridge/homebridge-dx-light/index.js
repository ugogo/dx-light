'use strict';

const { execFile } = require('child_process');
const fs = require('fs');
const path = require('path');

const PLUGIN_NAME = 'homebridge-dx-light';
const ACCESSORY_NAME = 'DXLight';

module.exports = (api) => {
  api.registerAccessory(PLUGIN_NAME, ACCESSORY_NAME, DxLightAccessory);
};

class DxLightAccessory {
  constructor(log, config, api) {
    this.log = log;
    this.config = config;
    this.api = api;
    this.Service = api.hap.Service;
    this.Characteristic = api.hap.Characteristic;

    this.name = config.name || 'DX Light';
    this.cliPath = config.cliPath || defaultCliPath();
    this.timeoutMs = Number(config.timeoutMs || 8000);
    this.brightness = clampPercent(config.defaultBrightness ?? 50);
    this.on = false;
    this.commandQueue = Promise.resolve();

    this.informationService = new this.Service.AccessoryInformation()
      .setCharacteristic(this.Characteristic.Manufacturer, 'Robobloq')
      .setCharacteristic(this.Characteristic.Model, 'DX Light')
      .setCharacteristic(this.Characteristic.Name, this.name);

    this.lightService = new this.Service.Lightbulb(this.name);
    this.lightService
      .getCharacteristic(this.Characteristic.On)
      .onGet(() => this.getOn())
      .onSet((value) => this.setOn(value));

    this.lightService
      .getCharacteristic(this.Characteristic.Brightness)
      .onGet(() => this.brightness)
      .onSet((value) => this.setBrightness(value));
  }

  getServices() {
    return [this.informationService, this.lightService];
  }

  async getOn() {
    try {
      const output = await this.enqueue(['state']);
      const match = output.match(/power:\s+(on|off)/i);
      if (match) {
        this.on = match[1].toLowerCase() === 'on';
      }
    } catch (error) {
      this.log.warn(`Could not read DX Light power state: ${error.message}`);
    }

    return this.on;
  }

  async setOn(value) {
    const enabled = Boolean(value);
    if (enabled) {
      await this.enqueue(['on', String(this.brightness / 100)]);
    } else {
      await this.enqueue(['off']);
    }

    this.on = enabled;
  }

  async setBrightness(value) {
    this.brightness = clampPercent(value);
    if (!this.on) {
      return;
    }

    await this.enqueue(['brightness', String(this.brightness / 100)]);
  }

  enqueue(args) {
    const run = () => this.runCli(args);
    const result = this.commandQueue.then(run, run);
    this.commandQueue = result.catch(() => {});
    return result;
  }

  runCli(args) {
    return new Promise((resolve, reject) => {
      execFile(
        this.cliPath,
        args,
        { timeout: this.timeoutMs },
        (error, stdout, stderr) => {
          if (error) {
            const detail = (stderr || stdout || error.message).trim();
            reject(new Error(detail || error.message));
            return;
          }

          resolve(stdout.toString());
        }
      );
    });
  }
}

function clampPercent(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) {
    return 50;
  }

  return Math.min(Math.max(Math.round(number), 0), 100);
}

function defaultCliPath() {
  const repoRoot = path.resolve(__dirname, '..', '..');
  const candidates = process.platform === 'win32'
    ? [
        path.join(repoRoot, 'Windows', 'DXLight.Cli', 'bin', 'Release', 'net8.0', 'DXLight.Cli.exe'),
        path.join(repoRoot, 'Windows', 'DXLight.Cli', 'bin', 'Debug', 'net8.0', 'DXLight.Cli.exe'),
      ]
    : [
        path.join(repoRoot, '.build', 'release', 'dx-light-cli'),
        path.join(repoRoot, '.build', 'debug', 'dx-light-cli'),
      ];

  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) {
      return candidate;
    }
  }

  return process.platform === 'win32' ? 'DXLight.Cli.exe' : 'dx-light-cli';
}
