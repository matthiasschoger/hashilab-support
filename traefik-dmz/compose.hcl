variable "base_domain" {
  default = "missing.environment.variable"
}

job "traefik-dmz" {
  datacenters = ["dmz"]
  type        = "service"

  # Traefik instance for the DMZ, routes traffic from cloudflared to the desired services
  group "traefik-dmz" {

    network {
      mode = "bridge"

      port "metrics" { to = 1080 } # Traefik metrics via API port
      port "crowdsec_metrics" { to = 6060 } # Crowdsec metrics 

      port "envoy_metrics_dmz_api" { to = 9102 }
      port "envoy_metrics_dmz_http" { to = 9103 }
      port "envoy_metrics_crowdsec_lapi" { to = 9104 }
    }

    ephemeral_disk {
      # Used to cache Crowdsec transient data, Nomad will try to preserve the disk between job updates.
      size    = 300 # MB
      migrate = true
    }

    service {
      name = "traefik-dmz-api"

      task = "server"
      port = 1080

      check {
        type     = "http"
        path     = "/ping"
        interval = "5s"
        timeout  = "2s"
        expose   = true # required for Connect
      }

      meta {
        metrics_port = "${NOMAD_HOST_PORT_metrics}"
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics_dmz_api}" # make envoy metrics port available in Consul
        crowdsec_metrics_port = "${NOMAD_HOST_PORT_crowdsec_metrics}"
      }
      connect {
        sidecar_service { 
          proxy {
            config {
              envoy_prometheus_bind_addr = "0.0.0.0:9102"
            }
          }
        }

        sidecar_task {
          resources {
            cpu    = 50
            memory = 48
          }
        }
      }

      tags = [ # registers the DMZ Traefik instance with the home instance
        "traefik.enable=true",
        "traefik.consulcatalog.connect=true",
        "traefik.http.routers.traefik-dmz.rule=Host(`dmz.lab.${var.base_domain}`)",
        "traefik.http.routers.traefik-dmz.entrypoints=websecure"
      ]
    }

    # Cloudflare entrypoint, is bound to localhost:80 in the cloudflared job via Consul Connect
    service {
      name = "traefik-dmz-http"

      port = 80

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics_dmz_http}" # make envoy metrics port available in Consul
      }
      connect {
        sidecar_service {
          proxy {
            config {
              envoy_prometheus_bind_addr = "0.0.0.0:9103"
            }
          }
        }

        sidecar_task {
          resources {
            cpu    = 50
            memory = 48
          }
        }
      }
    }

    service {
      name = "traefik-crowdsec-lapi"

      task = "server"
      port = 8080

      check {
        type     = "http"
        path     = "/health"
        interval = "5s"
        timeout  = "2s"
        expose   = true # required for Connect
      }

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics_crowdsec_lapi}" # make envoy metrics port available in Consul
      }
      connect {
        sidecar_service {
          proxy { 
            config {
              envoy_prometheus_bind_addr = "0.0.0.0:9104"
            }
          }
        }
      }
    }

    task "server" {

      driver = "docker"

      config {
        image = "traefik:latest"

        args = [ "--configFile=/local/traefik.yaml" ]
      }

      env {
        TZ = "Europe/Berlin"
      }

      template {
        destination = "${NOMAD_SECRETS_DIR}/certs/origin/${var.base_domain}.crt"
        perms = "600"
        data = <<EOH
{{- with nomadVar "nomad/jobs/traefik-dmz" }}{{- .origin_certificate }}{{- end }}
EOH
      }
      template {
        destination = "${NOMAD_SECRETS_DIR}/certs/origin/${var.base_domain}.key"
        perms = "600"
        data = <<EOH
{{- with nomadVar "nomad/jobs/traefik-dmz" }}{{- .origin_private_key }}{{- end }}
EOH
      }

      template {
        destination = "local/traefik.yaml"
        data        = file("traefik.yaml")
      }

      dynamic "template" {
        for_each = fileset(".", "conf/*")

        content {
          data            = file(template.value)
          destination     = "local/${template.value}"
        }
      }

      resources {
        memory = 256
        cpu    = 200
      }
    }
  

    # see https://blog.lrvt.de/configuring-crowdsec-with-traefik/
    task "crowdsec" {

      driver = "docker"

      lifecycle {
        hook = "prestart"
        sidecar = true
      }
      
      config {
        image = "crowdsecurity/crowdsec:latest"

        volumes = [
          "local/crowdsec/config.yaml.local:/etc/crowdsec/config.yaml.local",
          "local/crowdsec/acquis.d:/etc/crowdsec/acquis.d",
          "local/crowdsec/notifications/http.yaml:/etc/crowdsec/notifications/http.yaml",
        ]
      }

      env {
        TZ = "Europe/Berlin"

        COLLECTIONS = "crowdsecurity/traefik crowdsecurity/http-cve crowdsecurity/base-http-scenarios crowdsecurity/appsec-generic-rules crowdsecurity/appsec-virtual-patching crowdsecurity/appsec-crs"
        CROWDSEC_BYPASS_DB_VOLUME_CHECK = true
      }

      template { # fetch login information from container after executing "cscli enroll" and before restart
        destination = "secrets/crowdsec/online_api_credentials.yaml"
        data = <<EOH
url: https://api.crowdsec.net/
{{- with nomadVar "nomad/jobs/traefik-dmz" }}
login: "{{- .crowdsec_online_login }}"
password: "{{- .crowdsec_online_password }}"
{{- end }}
EOH
      }

      template {
        destination = "/local/crowdsec/config.yaml.local"
        data = <<EOH
common:
  # log_level: debug
  # log_level: error
api:
  server:
    online_client:
      credentials_path: "/secrets/crowdsec/online_api_credentials.yaml"
config_paths:
  # preserve stuff downloaded from Crowdsec Central between updates
  hub_dir: /alloc/data/crowdsec/hub
#db_config:
#  use_wal: true
prometheus:
  enabled: true
  level: full
  listen_addr: 0.0.0.0
EOH
      }

      template {
        destination = "/local/crowdsec/acquis.d/appsec.yaml"
        data = <<EOH
# appsec
listen_addr: 127.0.0.1:7422
appsec_config: crowdsecurity/appsec-default
name: AppSecComponent
source: appsec
labels:
  type: appsec
EOH
      }

      template {
        destination = "/local/crowdsec/acquis.d/traefik.yaml"
        data = <<EOH
# Traefik
poll_without_inotify: false
filenames:
  - {{ env "NOMAD_ALLOC_DIR" }}/traefik/*.log # Traefik access log location
labels:
  type: traefik
EOH
      }

      # FIXME: still experimental, does not work yet
      template { # http notification, which pushes lapi decisions to the Prometheus push endpoint
        destination = "/local/crowdsec/notifications/http.yaml"
        left_delimiter  = "[["
        right_delimiter = "]]"
        data = <<EOH
type: http
name: http_default
log_level: debug
# log_level: info

format: |
  {{- range $Alert := . -}}
  {{- range .Decisions -}}
  cs_lapi_decision{instance="schoger.net",country="{{$Alert.Source.Cn}}",asname="{{$Alert.Source.AsName}}",asnumber="{{$Alert.Source.AsNumber}}",latitude="{{$Alert.Source.Latitude}}",longitude="{{$Alert.Source.Longitude}}",iprange="{{$Alert.Source.Range}}",scenario="{{.Scenario}}",type="{{.Type}}",duration="{{.Duration}}",scope="{{.Scope}}",ip="{{.Value}}"} 1
  {{- end }}
  {{- end }}

[[- with nomadVar "nomad/jobs" ]]
url: https://prom-push.lab.[[ .base_domain ]]/metrics/job/crowdsec
[[- end ]]

method: POST
headers:
  Content-Type: text/plain

EOH
      }

      volume_mount {
        volume      = "crowdsec"
        destination = "/var/lib/crowdsec/data"
      }

      resources {
        memory = 256
        cpu    = 300
      }
    }

    volume "crowdsec" {
      type            = "csi"
      source          = "crowdsec"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }
  }
}
