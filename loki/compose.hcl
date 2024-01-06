job "loki" {
  datacenters = ["home"]
  type        = "service"

  group "loki" {

    constraint {
      attribute = "${node.class}"
      value     = "compute"
    }

    restart {
      attempts = 3
      delay = "1m"
      mode = "fail"
    }

    ephemeral_disk {
      # Used to store index, cache, WAL
      # Nomad will try to preserve the disk between job updates
      size    = 1000 # 1 GB
      migrate = true
    }

    network {
      mode = "bridge"

      port "envoy_metrics" { to = 9102 }
    }

    service {
      name = "loki"

      port = 3100

      check {
        type     = "http"
        path     = "/ready"
        interval = "10s"
        timeout  = "2s"
        expose   = true # required for Connect
      }

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=true",
        "traefik.http.routers.loki.rule=Host(`loki.lab.home`)",
        "traefik.http.routers.loki.entrypoints=websecure"
      ]

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics}" # make envoy metrics port available in Consul
      }
      connect {
        sidecar_service {
          proxy {
            config {
              protocol = "http"
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

    task "server" {
      driver = "docker"

      config {
        image = "grafana/loki:latest"
        args = [
          "-config.file=/local/config.yml",
          "-config.expand-env=true",
        ]
      }

      env {
        TZ = "Europe/Berlin"
      }

      template {
        data        = file("config.yml")
        destination = "local/config.yml"
      }

      resources {
        memory = 512
        cpu    = 100
      }

      volume_mount {
        volume      = "loki"
        destination = "/loki"
      }    
    }

    volume "loki" {
      type            = "csi"
      source          = "loki"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

  }
}