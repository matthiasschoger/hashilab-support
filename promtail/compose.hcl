job "promtail" {
  datacenters = ["home"]
  type        = "system"

  group "promtail" {

    network {
      mode = "bridge"

      port "envoy_metrics" { to = 9102 }
    }

    service {
      name = "promtail"

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics}" # make envoy metrics port available in Consul
      }
      connect {
        sidecar_service {
          proxy {
            config {
              envoy_prometheus_bind_addr = "0.0.0.0:9102"
            }
            upstreams {
              destination_name = "loki"
              local_bind_port  = 3100
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
        image = "grafana/promtail:latest"

        args = ["--config.file", "/local/promtail.yaml"]

        volumes = [
          "/var/log:/host/var/log:ro",
        ]
      }

      env {
        TZ = "Europe/Berlin"
      }

      resources {
        memory = 100
        cpu    = 100
      }

      template {
        destination = "local/promtail.yaml"
        data            = <<EOH
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://localhost:3100/loki/api/v1/push

scrape_configs:
- job_name: systemd-journal
  journal:
    labels:
      job: default/systemd-journal
    path: /host/var/log/journal
  relabel_configs:
  - source_labels:
    - __journal__systemd_unit
    target_label: app
  - source_labels:
    - __journal__hostname
    target_label: hostname
  - source_labels:
    - __journal_syslog_identifier
    target_label: syslog_identifier
EOH
      }
    }
  }
}