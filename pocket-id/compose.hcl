variable "base_domain" {
  default = "missing.environment.variable"
}

job "pocket-id" {
  datacenters = ["dmz"]
  type        = "service"

  group "pocket-id" {

    network {
      mode = "bridge"

      port "envoy_metrics" { to = 9102 }
    }

    service {
        name = "pocket-id"

        port = "1411"

        tags = [
          "dmz.enable=true",
          "dmz.consulcatalog.connect=true",
          "dmz.http.routers.pocket-id.rule=Host(`pocket-id.${var.base_domain}`)",
          "dmz.http.routers.pocket-id.entrypoints=cloudflare"
        ]

        check {
          type     = "http"
          path     = "/healthz"
          interval = "10s"
          timeout  = "2s"
          expose   = true # required for Connect
        }

        meta {
            envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics}" # make envoy metrics port available in Consul
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
    }

    task "server" {
      user = "1026:100" # matthias:users

      driver = "docker"

      config {
        image = "ghcr.io/pocket-id/pocket-id:latest"

        args = []
      }

      env {
        TZ = "Europe/Berlin"
      }

      template {
        destination = "${NOMAD_SECRETS_DIR}/vars.env"
        env             = true
        data            = <<EOH
# See the documentation for more information: https://pocket-id.org/docs/configuration/environment-variables

# These variables must be configured for your deployment:
APP_URL=https://pocket-id.${var.base_domain}

{{- with nomadVar "nomad/jobs/pocket-id" }}
ENCRYPTION_KEY="{{- .encryption_key }}"
{{- end }}

# These variables are optional but recommended to review:
TRUST_PROXY=true
MAXMIND_LICENSE_KEY=
PUID=1026
PGID=100
EOH
      }

      volume_mount {
        volume      = "pocket-id"
        destination = "/app/data"
      }

      resources {
        memory = 128
        cpu    = 50
      }
    }

    volume "pocket-id" {
      type            = "csi"
      source          = "pocket-id"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }
  }
}