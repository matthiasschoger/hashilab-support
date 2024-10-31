job "node-exporter" {
  datacenters = ["arbiter", "home", "dmz"]
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
        metrics_port = "${NOMAD_HOST_PORT_metrics}"
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics}" # make envoy metrics port available in Consul
      }
      connect {
        sidecar_service {
          proxy {
            config {
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
            memory = 48
            cpu    = 50
          }
        }
      }
    }

    task "server" {
      driver = "docker"

      config {
        image = "prom/node-exporter:latest"

        args  = [
          "--path.rootfs=/host",
          "--collector.mountstats" # required to collect traffic stats for NFS mounts
        ]

        volumes = [
          "/:/host:ro,rslave",
        ]
      }

      env {
        TZ = "Europe/Berlin"
      }

      resources {
        memory = 64
        cpu    = 50
      }
    }
  }
}