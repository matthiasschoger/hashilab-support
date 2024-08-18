job "cloudflared" {
  datacenters = ["dmz"]
  type        = "service"

  group "cloudflared" {

    network {
      mode = "bridge"

      port "metrics" { to = 9100 }
      port "envoy_metrics" { to = 9102 }
    }

    service {
        name = "ingress-cloudflare"
        
        meta {
            envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics}" # make envoy metrics port available in Consul
            metrics_port = "${NOMAD_HOST_PORT_metrics}"
        }
        connect {
            sidecar_service { 
                proxy {
                    config {
                        envoy_prometheus_bind_addr = "0.0.0.0:9102"
                    }
                    upstreams {
                        destination_name = "traefik-dmz-http"
                        local_bind_port  = 80
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
      driver = "docker"

      config {
        image = "cloudflare/cloudflared:latest"

        args = [
          "tunnel",
          "--config", "/secrets/config.yaml",
#          "--loglevel", "debug",
          "run", "home-lab"
        ]

        ports = ["metrics"]
      }

      template {
        destination = "secrets/config.yaml"
        data = <<EOH
{{- with nomadVar "nomad/jobs/cloudflared" }}

tunnel: {{ .tunnel }}
token: {{ .token }}

metrics: 0.0.0.0:9100

{{- end }}
EOH
      }

      resources {
        memory = 128
        cpu    = 50
      }
    }
  }
}