job "log-collection" {
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

    task "promtail" {
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
        memory = 150
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

  group "vector" {

    constraint {
      attribute = "${node.class}"
      value     = "compute"
    }

    network {
      mode = "bridge"

      port "envoy_metrics" { to = 9102 }
    }

    ephemeral_disk {
      size    = 500
      sticky  = true
    }

    service {
      name = "vector"

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

    task "vector" {
      driver = "docker"

      config {
        image = "timberio/vector:latest-alpine"
      }

      env {
        TZ = "Europe/Berlin"

        VECTOR_CONFIG = "/local/vector.yaml"
        VECTOR_REQUIRE_HEALTHY = "true"
      }

      resources {
        memory = 150
        cpu    = 100
      }

      template {
        destination = "local/vector.yaml"
        change_mode   = "signal"
        change_signal = "SIGHUP"
        # overriding the delimiters to [[ ]] to avoid conflicts with Vector's native templating, which also uses {{ }}
        left_delimiter = "[["
        right_delimiter = "]]"
        data            = <<EOH
data_dir: "alloc/data/vector/"
api:
  enabled: false
sources:
  logs:
    type: "docker_logs"
sinks:
  out:
    type: "console"
    inputs: ["logs"]
    encoding:
      codec: "json"
sinks:
  loki:
    type: "loki"
    inputs: ["logs"]
    endpoint: "http://localhost:3100"
    compression: "snappy"
    encoding:
      codec: "json"
    healthcheck:
      enabled: true
    labels:
      # See https://vector.dev/docs/reference/vrl/expressions/#path-example-nested-path
      job: "{{label.\"com.hashicorp.nomad.job_name\" }}"
      task: "{{label.\"com.hashicorp.nomad.task_name\" }}"
      group: "{{label.\"com.hashicorp.nomad.task_group_name\" }}"
#      namespace: "{{label.\"com.hashicorp.nomad.namespace\" }}"
      node: "{{label.\"com.hashicorp.nomad.node_name\" }}"
    # remove fields that have been converted to labels to avoid having the field twice
    remove_label_fields: true
EOH
      }

      # docker socket volume mount
      volume_mount {
        volume = "docker-sock"
        destination = "/var/run/docker.sock"
        read_only = true
      }
    }

    # docker socket volume
    volume "docker-sock" {
      type = "host"
      source = "docker-sock-ro"
      read_only = true
    }
  }
}