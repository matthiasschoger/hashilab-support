job "proton-bridge" {
  datacenters = ["home"]
  type        = "service"

  group "bridge" {

    network {
      mode = "bridge"

      port "envoy_metrics_smtp" { to = 9102 }
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

    # no IMAP service exposed at this point

    task "server" {
      driver = "docker"

      config {
        image = "shenxn/protonmail-bridge:latest"
      }

      resources {
        memory = 512
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