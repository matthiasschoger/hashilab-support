job "node-exporter" {
  datacenters = ["home"]
  type        = "system"

  group "node-exporter" {

    network {
      mode = "bridge"

      port "metrics" { }
      port "envoy_metrics" { to = 9102 }
    }

    service {
      name = "node-exporter"

      port = 9100

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics}" # make envoy metrics port available in Consul
        metrics_port = "${NOMAD_HOST_PORT_metrics}"
      }
      connect {
        sidecar_service {
          proxy {
            config {
              protocol = "http"
              envoy_prometheus_bind_addr = "0.0.0.0:9102"
            }
            expose {
              path {
                path            = "/metrics"
                protocol        = "http"
                local_path_port = 9100
                listener_port   = "metrics"
              }
            }
          }
        }

        sidecar_task {
          resources {
            cpu    = 50
            memory = 64
          }
        }
      }
    }

    task "server" {
      driver = "docker"

      config {
        image = "prom/node-exporter:latest"

        args  = ["--path.rootfs=/host"]

        volumes = [
          "/:/host:ro,rslave",
        ]
      }

      env {
        TZ = "Europe/Berlin"
      }

      resources {
        memory = 100
        cpu    = 100
      }
    }
  }
}