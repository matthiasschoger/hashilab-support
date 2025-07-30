variable "base_domain" {
  default = "missing.environment.variable"
}

job "prometheus" {
  datacenters = ["home"]
  type = "service"

  group "prometheus" {

    network {
      mode = "bridge"

      port "envoy_metrics_prometheus" { to = 9101 }
      port "envoy_metrics_pushgateway" { to = 9102 }
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

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics_prometheus}" # make envoy metrics port available in Consul
      }
      connect {
        sidecar_service {
          proxy {
            config {
              envoy_prometheus_bind_addr = "0.0.0.0:9101"
            }
          }
        }

        sidecar_task {
          resources {
            cpu    = 50
            memory = 32
          }
        }
      }
    }

    service {
      name = "prometheus-pushgateway"
      
      port = 9091

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
        "traefik.http.routers.prom-push.rule=Host(`prom-push.lab.${var.base_domain}`)",
        "traefik.http.routers.prom-push.entrypoints=websecure"
      ]

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics_pushgateway}" # make envoy metrics port available in Consul
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
            memory = 32
          }
        }
      }
    }

    task "server" {

      driver = "docker"

      user = "1026:100" # matthias:users

      config {
        image = "prom/prometheus:latest"

        args = [
                "--config.file", "/local/prometheus/prometheus.yaml",
                "--log.level", "warn"
               ]
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
        memory = 768
      }

      volume_mount {
        volume      = "prometheus"
        destination = "/prometheus"
      }    
    }

    # Push gateway, see https://github.com/sa06/prometheus-pushgateway/blob/master/README.md
    #  currently used by crowdsec to push geocoded intrusion attempts
    task "push-gateway" {
      driver = "docker"

      config {
        image = "prom/pushgateway:latest"
      }

      env {
        TZ = "Europe/Berlin"
      }

      resources {
        cpu    = 50
        memory = 24
      }
    }    

    # snmp exporter for the Synology metrics
    task "synology-exporter" {
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
        memory = 16
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
