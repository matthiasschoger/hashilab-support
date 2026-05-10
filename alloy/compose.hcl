variable "base_domain" {
  default = "missing.environment.variable"
}

job "alloy" {
  datacenters = ["arbiter", "home", "dmz"]
  type        = "system"

 update {
    max_parallel = 5
  }

  group "alloy" {

    network {
      mode = "bridge"

      port "metrics" { to = 9080 }
    }

    service {
      name = "alloy"

      port = "metrics"

      meta {
        metrics_port = "${NOMAD_HOST_PORT_metrics}"
      }

      check {
        type     = "http"
        path     = "/-/ready"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "server" {
      driver = "docker"

      config {
        image   = "grafana/alloy:latest"

        args = [
          "run",
           "--server.http.listen-addr=0.0.0.0:9080",
           "--storage.path=/var/lib/alloy/data",
          "/local/config.alloy"
        ]

        volumes = [
          "/var/run/docker.sock:/var/run/docker.sock:ro",
          "/var/log/journal:/alloy/var/log/journal:ro",
        ]
      }

      env {
        TZ = "Europe/Berlin"
      }

      resources {
        cpu    = 200
        memory = 320
      }

      # Alloy configuration in River/Alloy DSL
      template {
        destination = "local/config.alloy"
        data        = <<EOT
// ── General configurations ──────────────────────────────

logging {
  level  = "info"
  format = "logfmt"
}

// Use Loki as log entry sink
loki.write "loki_backend" {
  endpoint {
    url = "http://loki.lab.${var.base_domain}:3100/loki/api/v1/push"
  }
}

// ── Extract log files from all running Docker containers managed by Nomad ──────────────────────────────

loki.source.docker "docker_logs" {
  host          = "unix:///var/run/docker.sock"
  targets       = discovery.relabel.nomad_containers.output
  relabel_rules = discovery.relabel.nomad_containers.rules
  forward_to    = [loki.process.docker.receiver]

  labels        = { "type" = "container" }
}

discovery.docker "containers" {
  host = "unix:///var/run/docker.sock"
}

discovery.relabel "nomad_containers" {
  targets = discovery.docker.containers.targets

  // Map Nomad job metadata to log labels
  rule {
    source_labels = ["__meta_docker_container_label_com_hashicorp_nomad_job_name"]
    target_label  = "application"
  }
  rule {
    source_labels = ["__meta_docker_container_label_com_hashicorp_nomad_task_group_name"]
    target_label  = "group"
  }
  rule {
    source_labels = ["__meta_docker_container_label_com_hashicorp_nomad_task_name"]
    target_label  = "task"
  }
  rule {
    source_labels = ["__meta_consul_service"]
    target_label  = "servicename"
  }

  rule {
    source_labels = ["__meta_docker_container_label_com_hashicorp_nomad_node_name"]
    regex = "(.*)"
    replacement = "$1.home"
    target_label  = "machine"
  }
}

// filter out unnecessary noise in the log files
loki.process "docker" {
  forward_to = [loki.write.loki_backend.receiver]

  // First: narrow down by label using a LogQL selector, MongoDB is quite opinionated about filling the log with noise
  stage.match {
    selector = "{group=\"mongodb\",task=\"server\"}"

    // Then: drop lines containing the specific text
    stage.drop {
      expression          = "\"s\":\"I\",  \"c\":\"NETWORK\","      // all network messages on level "INFO"
      drop_counter_reason = "dropped_mongodb_noise"
    }
    stage.drop {
      expression          = "\"s\":\"I\",  \"c\":\"ACCESS\","       // all access messages on level "INFO"
      drop_counter_reason = "dropped_mongodb_noise"
    }
    stage.drop {
      expression          = "\"s\":\"I\",  \"c\":\"WTCHKPT\","      // all checkpoint messages on level "INFO"
      drop_counter_reason = "dropped_mongodb_noise"
    }
  }
}

// ── Extract log entries from journald ──────────────────────────────

loki.source.journal "debian" {
  max_age       = "12h"
  path          = "/alloy/var/log/journal"
  relabel_rules = loki.relabel.journal.rules
  forward_to    = [loki.process.journal.receiver]

  labels        = { "type" = "machine" }
}

// 2. Enrich log entries with useful labels
loki.relabel "journal" {
  forward_to = []

  rule {
    source_labels = ["__journal__systemd_unit"]
    target_label  = "application"
  }

  rule {
    source_labels = ["__journal__comm"]
    target_label  = "command"
  }

  rule {
    source_labels = ["__journal__hostname"]
    regex = "(.*)"
    replacement = "$1.home"
    target_label  = "machine"
  }

  // Syslog identifier (e.g. "sshd", "sudo", "kernel")
  rule {
    source_labels = ["__journal_syslog_identifier"]
    target_label  = "syslog_identifier"
  }

  // Map numeric syslog priority to human-readable level
  // 0=emerg 1=alert 2=crit 3=err 4=warning 5=notice 6=info 7=debug
  rule {
    source_labels = ["__journal__priority"]
    regex         = "0|1|2"
    target_label  = "level"
    replacement   = "critical"
  }
  rule {
    source_labels = ["__journal__priority"]
    regex         = "3"
    target_label  = "level"
    replacement   = "error"
  }
  rule {
    source_labels = ["__journal__priority"]
    regex         = "4"
    target_label  = "level"
    replacement   = "warning"
  }
  rule {
    source_labels = ["__journal__priority"]
    regex         = "5|6"
    target_label  = "level"
    replacement   = "info"
  }
  rule {
    source_labels = ["__journal__priority"]
    regex         = "7"
    target_label  = "level"
    replacement   = "debug"
  }
}

// Processing pipeline
loki.process "journal" {

  // Drop noisy or irrelevant entries — adjust to your needs
  stage.drop {
    source    = "unit"
    value     = "systemd-timesyncd.service"
    drop_counter_reason = "dropped_timesync"
  }

  // drop debug level entries in production
  stage.drop {
    source    = "level"
    value     = "debug"
    drop_counter_reason = "dropped_debug"
  }

  forward_to = [loki.write.loki_backend.receiver]
}

EOT
      }

      volume_mount {
        volume      = "alloy"
        destination = "/var/lib/alloy/data"
      }
    }

    # Dynamic Host Volume, see https://developer.hashicorp.com/nomad/docs/stateful-workloads/dynamic-host-volumes
    # In addition, make sure that the "alloy" host volume is registered on each node (has to be done seperately)
    volume "alloy" {
      type      = "host"
      source    = "alloy"

      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }
  }
}