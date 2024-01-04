job "prometheus" {
  datacenters = ["home"]
  type = "service"

  group "prometheus" {

    constraint {
      attribute = "${node.class}"
      value     = "compute"
    }

    restart {
      attempts = 3
      delay = "1m"
      mode = "fail"
    }

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
        "traefik.http.routers.prometheus.rule=Host(`prometheus.lab.home`)",
        "traefik.http.routers.prometheus.entrypoints=websecure"
      ]

      connect {
        sidecar_service {
          proxy {
            config {
              protocol = "http"
              envoy_prometheus_bind_addr = "0.0.0.0:9102"
            }
            upstreams {
              destination_name = "snmp-exporter"
              local_bind_port  = 9116
            }
            upstreams {
              destination_name = "unifi-exporter"
              local_bind_port  = 9130
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
        image = "prom/prometheus:latest"

        args = ["--config.file", "/local/prometheus/prometheus.yaml"]

        volumes = [
          "/etc/ssl/certs:/etc/ssl/certs:ro"    # use TLS certs from host OS, including the homelab cert
        ]      
      }

      template {
        data        = file("config/prometheus.yaml")
        destination = "local/prometheus/prometheus.yaml"
      }

      resources {
        cpu    = 200
        memory = 1000
      }

      volume_mount {
        volume      = "prometheus"
        destination = "/prometheus"
      }    
    }

    volume "prometheus" {
      type            = "csi"
      source          = "prometheus"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }
  }

  # SNMP exporter for Synology metrics
  group "snmp" {

    constraint {
      attribute = "${node.class}"
      value     = "compute"
    }

    restart {
      attempts = 3
      delay = "1m"
      mode = "fail"
    }

    network {
      mode = "bridge"

      port "envoy_metrics" { to = 9102 }
    }

    service {
      name = "snmp-exporter"
      
      port = 9116

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
            memory = 96
          }
        }
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

      template {
        data        = file("config/snmp-synology.yaml")
        destination = "local/snmp-synology.yaml"
      }

      resources {
        cpu    = 50
        memory = 64
      }
    }
  }

  # Unpoller to scrape metrics from the UDM via web API
  group "unifi" {

    constraint {
      attribute = "${node.class}"
      value     = "compute"
    }

    restart {
      attempts = 3
      delay = "1m"
      mode = "fail"
    }

    network {
      mode = "bridge"

      port "envoy_metrics" { to = 9102 }
    }

    service {
      name = "unifi-exporter"
      
      port = 9130

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
            memory = 100
          }
        }
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

      template {
        data        = file("config/unpoller.yaml")
        destination = "/local/unpoller.yaml"
      }

      resources {
        cpu    = 50
        memory = 100
      }
    }
  }
}
