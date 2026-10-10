local k = import 'k.libsonnet';
local g = (import 'github.com/jsonnet-libs/gateway-api-libsonnet/1.4/main.libsonnet').gateway;

local es = (import 'github.com/jsonnet-libs/external-secrets-libsonnet/1.1/main.libsonnet').nogroup.v1.externalSecret;

local image = import 'images.libsonnet';

local svc = k.core.v1.service;
local port = k.core.v1.servicePort;

local container = k.core.v1.container;
local envFrom = k.core.v1.envFromSource;
local mount = k.core.v1.volumeMount;

local sts = k.apps.v1.statefulSet;
local pvc = k.core.v1.persistentVolumeClaim;

{
  // TODO: Monitoring?
  wyoming: {
    // Text To Speech
    // https://github.com/OHF-Voice/wyoming-piper
    // https://github.com/OHF-Voice/piper1-gpl
    piper: {
      local this = self,

      labels:: { app: 'piper', wyoming: 'tts' },

      service: {
        ports:: {
          tts:
            port.withName('tts') +
            port.withProtocol('TCP') +
            port.withPort(10200) +
            port.withTargetPort(10200),

          http:
            port.withName('http') +
            port.withProtocol('TCP') +
            port.withPort(5000) +
            port.withTargetPort(5000),
        },

        headless:
          svc.new('piper-tts-headless', this.labels, [
            this.service.ports.tts,
            this.service.ports.http,
          ]) +
          svc.spec.withClusterIP('None'),

        app:
          svc.new('piper-tts', this.labels, [
            this.service.ports.tts,
            this.service.ports.http,
          ]),
      },

      healthCheckCmd:: [
        '/usr/src/.venv/bin/python3',
        '-m',
        'wyoming_piper.health_check',
        '--uri',
        'tcp://127.0.0.1:10200',
      ],

      container::
        image.forContainer('piper') +
        container.withArgs([
          // --backend {piper,omnivoice}
          //               TTS backend to use (default: piper)
          '--backend',
          'piper',
          // --voice VOICE         Default Piper voice to use (e.g., en_US-lessac-medium). Required for the piper
          //               backend.
          '--voice',
          'en_US-norman-medium',  // https://rhasspy.github.io/piper-samples/#en_US-norman-medium

          // --speaker SPEAKER     Name or id of speaker for default voice
          // --noise-scale NOISE_SCALE
          //               Generator noise
          // --length-scale LENGTH_SCALE
          //               Phoneme length
          // --noise-w-scale, --noise-w NOISE_W_SCALE
          //               Phoneme width noise
          // --sentence-silence SENTENCE_SILENCE
          //               Seconds of silence to add between sentences (default: no silence)
          // --auto-punctuation AUTO_PUNCTUATION
          //               Automatically add punctuation
          // --samples-per-chunk SAMPLES_PER_CHUNK
          // --no-streaming        Disable audio streaming on sentence boundaries
          // --update-voices       Download latest voices.json during startup
          // --use-cuda            Use CUDA if available (requires onnxruntime-gpu)

          // --web-server          Run a web UI for managing custom Piper/OmniVoice voices (requires the 'web'
          //               optional dependencies)
          '--web-server',
          // --web-server-host WEB_SERVER_HOST
          //               Host to bind the web UI to (default: 127.0.0.1)
          '--web-server-host',
          '0.0.0.0',
          // --web-server-port WEB_SERVER_PORT
          //               Port for the web UI (default: 5000)
          // --web-server-allow ADDRESS
          //               Only serve the web UI to this IP address or CIDR range, rejecting everything
          //               else (repeatable). The UI has no authentication, so restrict it whenever the
          //               bind address is reachable by anything but the intended client -- behind Home
          //               Assistant ingress that is the proxy, 172.30.32.2. Default: serve any address
          //               that can connect.
          '--web-server-allow',
          '10.42.0.0/8',

          // --omnivoice-steps OMNIVOICE_STEPS
          //               Number of MaskGIT decode steps for the omnivoice backend (default: 32, fewer is
          //               faster)
          // --omnivoice-ref-dir OMNIVOICE_REF_DIR
          //               Directory of reference voices for cloning (omnivoice backend), organized as
          //               <language>/<voice_name>/ref.{wav,txt}. Each is advertised as a voice; requests
          //               without a voice use the built-in speaker.
          // --omnivoice-language OMNIVOICE_LANGUAGE
          //               Language for the omnivoice backend (default: English)
          // --omnivoice-onnx-repo OMNIVOICE_ONNX_REPO
          //               HuggingFace repo id for the int4 ONNX graph (omnivoice backend). Overrides the
          //               built-in default.
        ]) +
        container.withPorts([
          { name: 'tts', containerPort: 10200 },
          { name: 'http', containerPort: 5000 },
        ]) +
        container.withVolumeMounts([
          mount.withMountPath('/data') +
          mount.withName('data'),
        ]) +
        container.startupProbe.exec.withCommand(this.healthCheckCmd) +
        container.startupProbe.withPeriodSeconds(30) +
        container.startupProbe.withTimeoutSeconds(20) +
        container.startupProbe.withFailureThreshold(10) +
        container.livenessProbe.exec.withCommand(this.healthCheckCmd) +
        container.livenessProbe.withPeriodSeconds(30) +
        container.livenessProbe.withTimeoutSeconds(20) +
        container.livenessProbe.withFailureThreshold(3),

      statefulSet:
        sts.new('piper-tts', 1, [this.container], [
          pvc.new('data') +
          pvc.spec.withAccessModes(['ReadWriteOnce']) +
          pvc.spec.resources.withRequests({ storage: '50Gi' }),
        ], null) +
        sts.metadata.withLabels(this.labels) +
        sts.spec.withServiceName(this.service.headless.metadata.name) +
        sts.spec.selector.withMatchLabels(this.labels) +
        sts.spec.template.metadata.withLabels(this.labels),

      local route = g.v1.httpRoute,
      local rule = route.spec.rules,
      route:
        route.new('piper-tts') +
        route.metadata.withNamespace($.namespace.metadata.name) +
        $._config.cilium.gateway.route() +
        route.spec.withHostnames(['tts.home.nlowe.dev']) +
        route.spec.withRules([
          rule.withBackendRefs([
            rule.backendRefs.withName(this.service.app.metadata.name) +
            rule.backendRefs.withNamespace($.namespace.metadata.name) +
            rule.backendRefs.withPort(5000),
          ]),
        ]),
    },

    // Speech To Text
    // https://github.com/OHF-Voice/wyoming-faster-whisper
    // https://github.com/SYSTRAN/faster-whisper
    whisper: {
      local this = self,

      labels:: { app: 'whisper', wyoming: 'stt' },

      service: {
        ports:: {
          stt:
            port.withName('stt') +
            port.withProtocol('TCP') +
            port.withPort(10300) +
            port.withTargetPort(10300),
        },

        headless:
          svc.new('whisper-stt-headless', this.labels, [
            this.service.ports.stt,
          ]) +
          svc.spec.withClusterIP('None'),

        app:
          svc.new('whisper-stt', this.labels, [
            this.service.ports.stt,
          ]),
      },

      hassTokenSecret:
        $._config.externalSecret.new('hass-whisper-stt-token', $.namespace.metadata.name) +
        es.spec.withData([
          //   --hass-token HASS_TOKEN
          //                         Long-lived access token for Home Assistant. Enables biasing toward the names of
          //                         exposed entities, areas, and floors (extra: hass). Keep it off the command line
          //                         with WYO_WHISPER_HASS_TOKEN_FILE
          es.spec.data.withSecretKey('WYO_WHISPER_HASS_TOKEN') +
          es.spec.data.remoteRef.withKey('e9ad3265-760c-43cb-a72e-b4db00321979'),
        ]),


      healthCheckCmd:: [
        '/usr/src/.venv/bin/python3',
        '-m',
        'wyoming_faster_whisper.health_check',
        '--uri',
        'tcp://127.0.0.1:10300',
      ],

      container::
        image.forContainer('whisper') +
        container.withArgs([
          //   --model MODEL         Name of model to use (or auto)
          '--model',
          'small-int8',  // TODO: What options are valid?

          //   --device DEVICE       Device to use for inference: cpu, cuda, or cuda:N (default: cpu). CUDA requires
          //                         the GPU image or GPU-enabled wheels; see README.
          '--device',
          'cpu',  // TODO: GPU?

          //   --language LANGUAGE   Default language to set for transcription (default: auto)
          '--language',
          'en',

          //   --compute-type COMPUTE_TYPE
          //                         Compute type for faster-whisper (float16, int8, etc.); defaults to float16 on
          //                         CUDA and to the model's own type on CPU
          //   --beam-size BEAM_SIZE
          //                         Size of beam during decoding (0 for auto)
          //   --cpu-threads CPU_THREADS
          //                         Number of CPU threads to use for inference (default: 4, faster-whisper, sherpa-
          //                         onnx, and qwen3-asr)
          //   --initial-prompt INITIAL_PROMPT
          //                         Optional text to provide as a prompt for the first window (faster-whisper); used
          //                         as biasing context for entity names (qwen3-asr)
          //   --whisper-task {transcribe,translate}
          //                         Task for whisper to do (default: transcribe)
          //   --vad-filter          Enable Silero VAD to filter out non-speech which can reduce hallucinations
          //                         (default: false, faster-whisper only)
          //   --vad-threshold VAD_THRESHOLD
          //                         VAD speech probability threshold (default: 0.5, faster-whisper only)
          //   --vad-min-speech-ms VAD_MIN_SPEECH_MS
          //                         VAD minimum speech duration in ms (default: 250, faster-whisper only)
          //   --vad-min-silence-ms VAD_MIN_SILENCE_MS
          //                         VAD minimum silence duration in ms to split (default: 2000, faster-whisper only)
          //   --vad-endpointing VAD_ENDPOINTING
          //                         End a command and send its transcript after this many seconds of VAD-detected
          //                         silence (default: wait for audio-stop)
          //   --vad-clip [STT_LIBRARY ...]
          //                         Use pysilero-vad to clip leading/trailing silence before transcription (default:
          //                         disabled). Pass --vad-clip for every library, or name the libraries it applies
          //                         to, e.g. --vad-clip qwen3-asr
          //   --vad-clip-threshold VAD_CLIP_THRESHOLD
          //                         Speech probability threshold for --vad-clip (default: 0.5)
          //   --vad-clip-pad-ms VAD_CLIP_PAD_MS
          //                         Context kept around speech for --vad-clip in ms (default: 400)
          //   --stt-library {auto,faster-whisper,transformers,sherpa,onnx-asr,funasr,qwen3-asr}
          //                         Set library to use for speech-to-text (may require extra dependencies)
          //   --sherpa-streaming    Use sherpa-onnx OnlineRecognizer for true streaming transcription (sherpa only;
          //                         requires a streaming model, e.g. a streaming zipformer)

          //   --hass-api HASS_API   URL of the Home Assistant API (default: http://homeassistant.local:8123/api)
          '--hass-api',
          'http://hass.smart-home.svc.cluster.local.:8123/api',
          //   --hass-refresh-seconds HASS_REFRESH_SECONDS
          //                         Minimum seconds between name refreshes (default: 0, refresh on every utterance)
          //   --hass-prompt-max-tokens HASS_PROMPT_MAX_TOKENS
          //                         Token budget for names in the prompt (default: 200, max useful: 223 for Whisper)
          //   --hass-prompt-timeout HASS_PROMPT_TIMEOUT
          //                         Seconds to wait for an unfinished name refresh before transcribing with the
          //                         previous names (default: 1.0)

          // Every option can also be set from the environment: --some-option reads WYO_WHISPER_SOME_OPTION, or
          // WYO_WHISPER_SOME_OPTION_FILE to read the value out of a file (docker secrets). Command-line arguments
          // win over both.
        ]) +
        container.withEnvFrom([
          envFrom.secretRef.withName(this.hassTokenSecret.metadata.name),
        ]) +
        container.withPorts([
          { name: 'stt', containerPort: 10300 },
        ]) +
        container.withVolumeMounts([
          mount.withMountPath('/data') +
          mount.withName('data'),
        ]) +
        container.startupProbe.exec.withCommand(this.healthCheckCmd) +
        container.startupProbe.withPeriodSeconds(30) +
        container.startupProbe.withTimeoutSeconds(20) +
        container.startupProbe.withFailureThreshold(10) +
        container.livenessProbe.exec.withCommand(this.healthCheckCmd) +
        container.livenessProbe.withPeriodSeconds(30) +
        container.livenessProbe.withTimeoutSeconds(20) +
        container.livenessProbe.withFailureThreshold(3),

      statefulSet:
        sts.new('whisper-stt', 1, [this.container], [
          pvc.new('data') +
          pvc.spec.withAccessModes(['ReadWriteOnce']) +
          pvc.spec.resources.withRequests({ storage: '50Gi' }),
        ], null) +
        sts.metadata.withLabels(this.labels) +
        sts.spec.withServiceName(this.service.headless.metadata.name) +
        sts.spec.selector.withMatchLabels(this.labels) +
        sts.spec.template.metadata.withLabels(this.labels),
    },
  },
}
