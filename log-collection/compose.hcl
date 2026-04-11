variable "base_domain" {
  default = "missing.environment.variable"
}

job "log-collection" {
  datacenters = ["arbiter", "home", "dmz"]
  type        = "system"

  group "alloy" {

    network {
      mode = "bridge"

      port "health" { to = 9080 }
    }

    ephemeral_disk {
      migrate = true
    }

    service {
      name = "alloy"

      port = "health"

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
          "--storage.path=${NOMAD_ALLOC_DIR}/data",  # important to persist the current position over container re-deployments
          "/local/config.alloy"
        ]

        volumes = [
          "/var/run/docker.sock:/var/run/docker.sock",
          "/opt/nomad/data/alloc:/alloy/nomad/alloc:ro"
        ]

        privileged = true
      }

      env {
        TZ = "Europe/Berlin"
      }

      # Alloy configuration in River/Alloy DSL
      template {
        destination = "local/config.alloy"
        data        = <<EOT
// ── 0. General configurations ──────────────────────────────

logging {
  level  = "info"
  format = "logfmt"
}

// ── 1. Discover all running Docker containers ──────────────────────────────
discovery.docker "containers" {
  host = "unix:///var/run/docker.sock"
}

// ── 2. Relabel: extract Nomad metadata from Docker labels ──────────────────
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

// ── 3. Collect logs from Docker containers ─────────────────────────────────
loki.source.docker "docker_logs" {
  host          = "unix:///var/run/docker.sock"
  targets       = discovery.relabel.nomad_containers.output
  relabel_rules = discovery.relabel.nomad_containers.rules
  labels        = { "platform" = "nomad", "type" = "container" }
 forward_to    = [loki.write.loki_backend.receiver]
//  forward_to    = [loki.process.filter_old_docker_logs.receiver]
}

// ── 4. Also tail Nomad alloc logs directly from the filesystem ────────────
local.file_match "alloc_logs" {
  path_targets = [{
    __path__ = "/alloy/nomad/alloc/**/alloc/logs/*.std*.[0-9]*",
    __path_exclude__ = "/alloy/nomad/alloc/**/alloc/logs/{connect-,envoy_bootstrap}*",
    platform  = "nomad",
    source    = "alloc_logs",
  }]
}

loki.source.file "alloc_log_files" {
  targets    = local.file_match.alloc_logs.targets
  forward_to = [loki.write.loki_backend.receiver]
  tail_from_end = true    // ← skips all pre-existing content on first start
}

// ── 5. Write to Loki ───────────────────────────────────────────────────────
loki.write "loki_backend" {
  endpoint {
    url = "http://loki.lab.${var.base_domain}:3100/loki/api/v1/push"
  }
}

EOT
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }
  }
}