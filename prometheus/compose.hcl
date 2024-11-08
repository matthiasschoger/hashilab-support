variable "base_domain" {
  default = "missing.environment.variable"
}

job "prometheus" {
  datacenters = ["home"]
  type = "service"

  group "prometheus" {

    network {
      mode = "bridge"
    }

    service {
      name = "prometheus"
      
      port = 9090

      check {
        type     = "http"
        path     = "/-/ready"
        interval = "5s"
        timeout  = "2s"
        expose   = true # required for Connect
      }

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=true",
        "traefik.http.routers.prometheus.rule=Host(`prometheus.lab.${var.base_domain}`)",
        "traefik.http.routers.prometheus.entrypoints=websecure"
      ]

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

    task "server" {

      driver = "docker"

      user = "1026:100" # matthias:users

      config {
        image = "prom/prometheus:latest"

        args = ["--config.file", "/local/prometheus/prometheus.yaml"]
      }

      env {
        TZ = "Europe/Berlin"
      }

      template {
        data        = file("config/prometheus.yaml")
        destination = "local/prometheus/prometheus.yaml"
      }

      resources {
        cpu    = 1500
        memory = 1536
      }

      volume_mount {
        volume      = "prometheus"
        destination = "/prometheus"
      }    
    }

    # snmp exporter for Prometheus, more like a proxy to query other machines via SNMP
    task "snmp-exporter" {
      driver = "docker"

      config {
        image = "prom/snmp-exporter:latest"

        args  = [
          "--config.file=/local/snmp-synology.yaml"
        ]
      }

      env {
        TZ = "Europe/Berlin"
      }

      template {
        data        = file("config/snmp-synology.yaml")
        destination = "local/snmp-synology.yaml"
      }

      resources {
        cpu    = 50
        memory = 32
      }
    }

    # Unifi exporter for Prometheus
    task "unifi-exporter" {
      driver = "docker"

      config {
        image = "ghcr.io/unpoller/unpoller:latest"

        args  = [
          "--config=/local/unpoller.yaml"
        ]
      }

      env {
        TZ = "Europe/Berlin"
      }

      template {
        data        = file("config/unpoller.yaml")
        destination = "/local/unpoller.yaml"
      }

      resources {
        cpu    = 50
        memory = 48
      }
    }
  
    volume "prometheus" {
      type            = "csi"
      source          = "prometheus"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }
  }
}
