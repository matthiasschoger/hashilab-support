job "proton-bridge" {
  datacenters = ["home"]
  type        = "service"

  group "bridge" {

    constraint {
      attribute = "${node.class}"
      value     = "compute"
    }

    network {
      mode = "bridge"

      port "envoy_metrics_smtp" { to = 9102 }
      port "envoy_metrics_imap" { to = 9103 }
    }

    service {
      name = "protonmail-smtp"

      port = 1025

     meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics_smtp}" # make envoy metrics port available in Consul
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
            memory = 64
          }
        }
      }    
    }

    service {
      name = "protonmail-imap"

      port = 1143

     meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics_imap}" # make envoy metrics port available in Consul
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
            memory = 64
          }
        }
      }    
    }

    task "server" {
      driver = "docker"

      config {
        image = "shenxn/protonmail-bridge:latest"
      }

      resources {
        memory = 500
        cpu    = 200
      }

      volume_mount {
        volume      = "proton"
        destination = "/root"
      }
    }

    volume "proton" {
      type            = "csi"
      source          = "proton"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }
  }
}