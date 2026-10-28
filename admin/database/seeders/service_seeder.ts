import Service from '#models/service'
import { BaseSeeder } from '@adonisjs/lucid/seeders'
import { ModelAttributes } from '@adonisjs/lucid/types/model'
import env from '#start/env'
import { SERVICE_NAMES } from '../../constants/service_names.js'

export default class ServiceSeeder extends BaseSeeder {
  // Use environment variable with fallback to production default
  private static NOMAD_STORAGE_ABS_PATH = env.get(
    'NOMAD_STORAGE_PATH',
    '/opt/project-nomad/storage'
  )
  private static DEFAULT_SERVICES: Omit<
    ModelAttributes<Service>,
    'created_at' | 'updated_at' | 'metadata' | 'id' | 'available_update_version' | 'update_checked_at'
  >[] = [
    {
      service_name: SERVICE_NAMES.KIWIX,
      friendly_name: 'Information Library',
      powered_by: 'Kiwix',
      display_order: 1,
      description:
        'Offline access to Wikipedia, medical references, how-to guides, and encyclopedias',
      icon: 'IconBooks',
      container_image: 'ghcr.io/kiwix/kiwix-serve:3.8.1',
      source_repo: 'https://github.com/kiwix/kiwix-tools',
      container_command: '*.zim --address=all',
      container_config: JSON.stringify({
        HostConfig: {
          RestartPolicy: { Name: 'unless-stopped' },
          Binds: [`${ServiceSeeder.NOMAD_STORAGE_ABS_PATH}/zim:/data`],
          PortBindings: { '8080/tcp': [{ HostPort: '8090' }] },
        },
        ExposedPorts: { '8080/tcp': {} },
      }),
      ui_location: '8090',
      installed: false,
      installation_status: 'idle',
      is_dependency_service: false,
      depends_on: null,
    },
    {
      service_name: SERVICE_NAMES.QDRANT,
      friendly_name: 'Qdrant Vector Database',
      powered_by: null,
      display_order: 100, // Dependency service, not shown directly
      description: 'Vector database for storing and searching embeddings',
      icon: 'IconRobot',
      container_image: 'qdrant/qdrant:v1.16',
      source_repo: 'https://github.com/qdrant/qdrant',
      container_command: null,
      container_config: JSON.stringify({
        HostConfig: {
          RestartPolicy: { Name: 'unless-stopped' },
          Binds: [`${ServiceSeeder.NOMAD_STORAGE_ABS_PATH}/qdrant:/qdrant/storage`],
          PortBindings: { '6333/tcp': [{ HostPort: '6333' }], '6334/tcp': [{ HostPort: '6334' }] },
        },
        ExposedPorts: { '6333/tcp': {}, '6334/tcp': {} },
      }),
      ui_location: '6333',
      installed: false,
      installation_status: 'idle',
      is_dependency_service: true,
      depends_on: null,
    },
    {
      service_name: SERVICE_NAMES.OLLAMA,
      friendly_name: 'AI Assistant',
      powered_by: 'Ollama',
      display_order: 3,
      description: 'Local AI chat that runs entirely on your hardware - no internet required',
      icon: 'IconWand',
      container_image: 'ollama/ollama:0.34.4',
      source_repo: 'https://github.com/ollama/ollama',
      container_command: 'serve',
      container_config: JSON.stringify({
        HostConfig: {
          RestartPolicy: { Name: 'unless-stopped' },
          Binds: [`${ServiceSeeder.NOMAD_STORAGE_ABS_PATH}/ollama:/root/.ollama`],
          PortBindings: { '11434/tcp': [{ HostPort: '11434' }] },
        },
        ExposedPorts: { '11434/tcp': {} },
      }),
      ui_location: '/chat',
      installed: false,
      installation_status: 'idle',
      is_dependency_service: false,
      depends_on: SERVICE_NAMES.QDRANT,
    },
    {
      service_name: SERVICE_NAMES.CYBERCHEF,
      friendly_name: 'Data Tools',
      powered_by: 'CyberChef',
      display_order: 11,
      description: 'Swiss Army knife for data encoding, encryption, and analysis',
      icon: 'IconChefHat',
      container_image: 'ghcr.io/gchq/cyberchef:10.22.1',
      source_repo: 'https://github.com/gchq/CyberChef',
      container_command: null,
      container_config: JSON.stringify({
        HostConfig: {
          RestartPolicy: { Name: 'unless-stopped' },
          PortBindings: { '80/tcp': [{ HostPort: '8100' }] },
        },
        ExposedPorts: { '80/tcp': {} },
      }),
      ui_location: '8100',
      installed: false,
      installation_status: 'idle',
      is_dependency_service: false,
      depends_on: null,
    },
    {
      service_name: SERVICE_NAMES.FLATNOTES,
      friendly_name: 'Notes',
      powered_by: 'FlatNotes',
      display_order: 10,
      description: 'Simple note-taking app with local storage',
      icon: 'IconNotes',
      container_image: 'dullage/flatnotes:v5.5.4',
      source_repo: 'https://github.com/dullage/flatnotes',
      container_command: null,
      container_config: JSON.stringify({
        HostConfig: {
          RestartPolicy: { Name: 'unless-stopped' },
          PortBindings: { '8080/tcp': [{ HostPort: '8200' }] },
          Binds: [`${ServiceSeeder.NOMAD_STORAGE_ABS_PATH}/flatnotes:/data`],
        },
        ExposedPorts: { '8080/tcp': {} },
        Env: ['FLATNOTES_AUTH_TYPE=none'],
      }),
      ui_location: '8200',
      installed: false,
      installation_status: 'idle',
      is_dependency_service: false,
      depends_on: null,
    },
    {
      service_name: SERVICE_NAMES.KOLIBRI,
      friendly_name: 'Education Platform',
      powered_by: 'Kolibri',
      display_order: 2,
      description: 'Interactive learning platform with video courses and exercises',
      icon: 'IconSchool',
      container_image: 'treehouses/kolibri:0.12.8',
      source_repo: 'https://github.com/learningequality/kolibri',
      container_command: null,
      container_config: JSON.stringify({
        HostConfig: {
          RestartPolicy: { Name: 'unless-stopped' },
          PortBindings: { '8080/tcp': [{ HostPort: '8300' }] },
          Binds: [`${ServiceSeeder.NOMAD_STORAGE_ABS_PATH}/kolibri:/root/.kolibri`],
        },
        ExposedPorts: { '8080/tcp': {} },
      }),
      ui_location: '8300',
      installed: false,
      installation_status: 'idle',
      is_dependency_service: false,
      depends_on: null,
    },
    {
      service_name: SERVICE_NAMES.RADIO,
      friendly_name: 'Radio',
      powered_by: 'welle.io',
      display_order: 12,
      description:
        'RTL-SDR powered DAB/DAB+ radio receiver with a browser UI for scanning and playback',
      icon: 'IconRadio',
      container_image: 'project-nomad-local/radio:latest',
      source_repo: 'https://github.com/AlbrechtL/welle.io',
      container_command: '-F rtl_sdr -w 8000 -c /config/welle-cli.ini',
      container_config: JSON.stringify({
        HostConfig: {
          RestartPolicy: { Name: 'unless-stopped' },
          Privileged: true,
          PortBindings: { '8000/tcp': [{ HostPort: '8400' }] },
          Binds: [
            `${ServiceSeeder.NOMAD_STORAGE_ABS_PATH}/radio:/config`,
            '/dev/bus/usb:/dev/bus/usb',
            '/run/udev:/run/udev:ro',
          ],
        },
        ExposedPorts: { '8000/tcp': {} },
      }),
      ui_location: '8400',
      installed: false,
      installation_status: 'idle',
      is_dependency_service: false,
      depends_on: null,
    },
    {
      service_name: SERVICE_NAMES.OPENWEBRX,
      friendly_name: 'Spectrum Analyzer',
      powered_by: 'OpenWebRX+',
      display_order: 13,
      description:
        'Raw SDR web receiver and signal analysis interface for spectrum browsing and protocol decoding',
      icon: 'IconAntennaBars5',
      container_image: 'slechev/openwebrxplus:latest',
      source_repo: 'https://www.openwebrx.de/',
      container_command: null,
      container_config: JSON.stringify({
        Env: ['TZ=Europe/Madrid', 'OPENWEBRX_ADMIN_USER=admin', 'OPENWEBRX_ADMIN_PASSWORD=password'],
        HostConfig: {
          RestartPolicy: { Name: 'unless-stopped' },
          Privileged: true,
          PortBindings: { '8073/tcp': [{ HostPort: '8500' }] },
          Binds: [
            `${ServiceSeeder.NOMAD_STORAGE_ABS_PATH}/openwebrx-config:/etc/openwebrx`,
            `${ServiceSeeder.NOMAD_STORAGE_ABS_PATH}/openwebrx:/var/lib/openwebrx`,
            '/dev/bus/usb:/dev/bus/usb',
            '/run/udev:/run/udev:ro',
          ],
        },
        ExposedPorts: { '8073/tcp': {} },
      }),
      ui_location: '8500',
      installed: false,
      installation_status: 'idle',
      is_dependency_service: false,
      depends_on: null,
    },
    {
      service_name: SERVICE_NAMES.NODERED,
      friendly_name: 'Node-RED',
      powered_by: 'Node-RED',
      display_order: 14,
      description: 'Flow-based automation and integration workspace with a browser editor',
      icon: 'IconBrandNodejs',
      container_image: 'nodered/node-red:4.1.1',
      source_repo: 'https://github.com/node-red/node-red',
      container_command: null,
      container_config: JSON.stringify({
        HostConfig: {
          RestartPolicy: { Name: 'unless-stopped' },
          PortBindings: { '1880/tcp': [{ HostPort: '1880' }] },
          Binds: [`${ServiceSeeder.NOMAD_STORAGE_ABS_PATH}/nodered:/data`],
        },
        ExposedPorts: { '1880/tcp': {} },
      }),
      ui_location: '1880',
      installed: false,
      installation_status: 'idle',
      is_dependency_service: false,
      depends_on: null,
    },
    {
      service_name: SERVICE_NAMES.MOSQUITTO,
      friendly_name: 'Mosquitto',
      powered_by: 'Eclipse Mosquitto',
      display_order: 15,
      description: 'Lightweight MQTT broker for local message routing, automation, and integrations',
      icon: 'IconBroadcast',
      container_image: 'eclipse-mosquitto:2.0.21',
      source_repo: 'https://github.com/eclipse-mosquitto/mosquitto',
      container_command: null,
      container_config: JSON.stringify({
        HostConfig: {
          RestartPolicy: { Name: 'unless-stopped' },
          PortBindings: { '1883/tcp': [{ HostPort: '1883' }] },
          Binds: [
            `${ServiceSeeder.NOMAD_STORAGE_ABS_PATH}/mosquitto/data:/mosquitto/data`,
            `${ServiceSeeder.NOMAD_STORAGE_ABS_PATH}/mosquitto/log:/mosquitto/log`,
          ],
        },
        ExposedPorts: { '1883/tcp': {} },
      }),
      ui_location: '',
      installed: false,
      installation_status: 'idle',
      is_dependency_service: false,
      depends_on: null,
    },
  ]

  async run() {
    const existingServices = await Service.query().select('service_name')
    const existingServiceNames = new Set(existingServices.map((service) => service.service_name))

    const newServices = ServiceSeeder.DEFAULT_SERVICES.filter(
      (service) => !existingServiceNames.has(service.service_name)
    )

    await Service.createMany([...newServices])
  }
}
