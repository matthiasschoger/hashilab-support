variable "base_domain" {
  default = "missing.environment.variable"
}

job "log-collection" {
  datacenters = ["arbiter", "home", "dmz"]
  type        = "system"

  group "promtail" {

    network {
      mode = "bridge"

      port "envoy_metrics" { to = 9102 }
    }

    # TODO: rework to send the logs via the Consul Connect SDN
    # service {
    #   name = "promtail"

    #   meta {
    #     envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics}" # make envoy metrics port available in Consul
    #   }
    #   connect {
    #     sidecar_service {
    #       proxy {
    #         config {
    #           envoy_prometheus_bind_addr = "0.0.0.0:9102"
    #         }

    #         upstreams {
    #             destination_name = "loki"
    #             local_bind_port  = 3100
    #         }
    #       }
    #     }

    #     sidecar_task {
    #       resources {
    #         cpu    = 50
    #         memory = 48
    #       }
    #     }
    #   }
    # }

    task "promtail" {
      driver = "docker"

      config {
#        image = "grafana/promtail:latest"
        image = "grafana/promtail:3.5.8"

        args = ["--config.file", "/local/promtail.yaml"]

        volumes = [
          "/var/log:/host/var/log:ro",
        ]
      }

      env {
        TZ = "Europe/Berlin"
      }

      resources {
        memory = 128
        cpu    = 50
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
  - url: http://loki.lab.${var.base_domain}:3100/loki/api/v1/push
#  - url: http://localhost:3100/loki/api/v1/push

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

/*
  # Vector group
  group "vector" {

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

      port = 8686

      check {
        type     = "http"
        path     = "/health"
        interval = "30s"
        timeout  = "5s"
        expose   = true # required for Connect
      }

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
            cpu    = 50
            memory = 48
          }
        }
      }
    }

    task "vector" {
      driver = "docker"

      config {
        image = "timberio/vector:latest-debian"

        volumes = [
          "/etc/machine-id:/etc/machine-id:ro" # required for Vector?
        ]
      }

      env {
        TZ     = "Europe/Berlin"
        LC_ALL = "C.UTF-8" # required for UTF-8 support

        VECTOR_CONFIG = "/local/vector.yaml"
      }

      resources {
        memory = 512
        cpu    = 50
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
  enabled: true
healthchecks:
  require_healthy: true

sources:
  docker_logs:
    type: "docker_logs"

transforms:
  throttled_docker_logs:
    type: "throttle"
    inputs:
      - "docker_logs"
    threshold: 1
    window_secs: 10
  translormed_logs:
    type: "remap"
    inputs
      -  "logs"
    source: '''
            .debug = parse_key_value!(.message)
            .job_name = split(get!(value: .label, path: ["com.hashicorp.nomad.job_name"]), "/")[0] ?? get!(value: .label, path: ["com.hashicorp.nomad.job_name"])
    '''
sinks:
  out:
    type: "console"
    inputs: 
      - "docker_logs"
    target: "stdout"
    encoding:
      codec: "json"
  loki:
    type: "loki"
    endpoint: "http://lab.${var.base_domain}:3100"
    healthcheck:
      enabled: true
    inputs: 
#      - "throttled_docker_logs"
      - "translormed_logs"
    encoding:
      codec: "json"
    buffer
      type: "memory"
#    batch:
#      max_bytes: 1000000
#      max_events: 1
    labels:
      app: "containers"
      # See https://vector.dev/docs/reference/vrl/expressions/#path-example-nested-path
      job: "{{label.\"com.hashicorp.nomad.job_name\" }}"
      task: "{{label.\"com.hashicorp.nomad.task_name\" }}"
      group: "{{label.\"com.hashicorp.nomad.task_group_name\" }}"
      node: "{{label.\"com.hashicorp.nomad.node_name\" }}"
    remove_label_fields: true # remove fields that have been converted to labels to avoid having the field twice
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
*/
}