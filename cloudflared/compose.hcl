job "cloudflared" {
  datacenters = ["home"]
  type        = "service"

  group "cloudflared" {

    constraint {
      attribute = "${node.class}"
      value     = "compute"
    }

    network {
      mode = "bridge"

      port "metrics" { }
      port "envoy_metrics" { to = 9102 }
    }

    service {
        name = "cloudflared-ingress"
        
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
                        destination_name = "traefik-cloudflare"
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

        privileged = true

        args = [
          "tunnel",
          "--config", "/secrets/config.yaml",
#          "--loglevel", "debug",
          "run", "home"
        ]

        ports = ["metrics"]
      }

      template {
        destination = "secrets/config.yaml"
        data = <<EOH
{{- with nomadVar "nomad/jobs/cloudflared" }}

tunnel: {{ .tunnel }}
token: {{ .token }}
warp-routing:
    enabled: true
metrics: localhost:{{ env "NOMAD_PORT_metrics" }}

{{- end }}
EOH
      }

      resources {
        memory = 500
        cpu    = 200
      }
    }
  }
}