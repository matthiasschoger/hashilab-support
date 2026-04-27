variable "base_domain" {
  default = "missing.environment.variable"
}

job "alloy-ui" {
  datacenters = ["home"]
  type        = "service"

  group "alloy-ui" {

    network {
      mode = "bridge"

      port "envoy_metrics" { to = 9102 }
    }

    ephemeral_disk {
      migrate = true
    }

    service {
      name = "alloy-ui"

      port = 9080

      check {
        type     = "http"
        path     = "/-/ready"
        interval = "10s"
        timeout  = "2s"
        expose   = true
      }

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=true",
        "traefik.http.routers.alloy-ui.rule=Host(`alloy.lab.${var.base_domain}`)"
      ]

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
            memory = 32
          }
        }
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
          "--stability.level=experimental",          # enables Alloy UI
          "/local/config.alloy"
        ]
      }

      env {
        TZ = "Europe/Berlin"
      }

      # Alloy configuration in River/Alloy DSL
      template {
        destination = "local/config.alloy"
        data        = <<EOT
// ── General configurations ──────────────────────────────

logging {
  level  = "warn"
  format = "logfmt"
}

// ── Grafana Alloy — Consul-based peer discovery ──────────────────────────────

// 1. Discover peer Alloy nodes from Consul
discovery.consul "alloy_peers" {
  server  = "http://consul.service.consul:8500"   // Consul agent
  services = [ "alloy" ]

  // Uncomment if Consul ACLs are enabled
  // token = env("CONSUL_TOKEN")
}

// 2. Relabel discovered peers
discovery.relabel "alloy_peers" {
  targets = discovery.consul.alloy_peers.targets

  // Only keep healthy nodes
  rule {
    source_labels = ["__meta_consul_health"]
    regex         = "passing"
    action        = "keep"
  }

  // Attach the node name as a label
  rule {
    source_labels = ["__meta_consul_node"]
    target_label  = "node"
  }

  // Attach the datacenter as a label
  rule {
    source_labels = ["__meta_consul_dc"]
    target_label  = "datacenter"
  }
}

// 3. Scrape metrics from all discovered Alloy peers
//    This gives you a unified cluster view in Grafana
prometheus.scrape "alloy_peers" {

//  clustering {
//    enabled = true
//  }

  targets         = discovery.relabel.alloy_peers.output
  forward_to      = [prometheus.remote_write.default.receiver]
  scrape_interval = "30s"

  // Use Alloy's built-in metrics endpoint
  metrics_path = "/metrics"
}

// 4. Ship metrics to Prometheus
prometheus.remote_write "default" {
  endpoint {
    url = "http://prometheus.lab.${var.base_domain}/api/v1/write"
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