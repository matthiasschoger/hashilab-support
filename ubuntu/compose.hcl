job "ubuntu" {
  datacenters = ["home"]
  type        = "service"

  group "ubuntu" {

    constraint {
      attribute = "${node.class}"
      value     = "dmz"
    }

    network {
      mode = "bridge"
    }

    service {
      name = "ubuntu"

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
            cpu    = 100
            memory = 64
          }
        }
      }
    }

    task "server" {
      driver = "docker"

      config {
        image = "ubuntu:rolling"

        args = ["sleep","infinity"]

        volumes = [
          "/etc/ssl/certs:/etc/ssl/certs:ro"    # use TLS certs from host OS, including the Schoger Home cert
        ]      
      }

      env {
        TZ = "Europe/Berlin"
      }

      resources {
        memory = 200
        cpu    = 50
      }
    }
  }
}