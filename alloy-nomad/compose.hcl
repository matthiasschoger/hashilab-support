variable "base_domain" {
  default = "missing.environment.variable"
}

job "log-collection-nomad" {
  datacenters = ["home"]
  type        = "service"

  group "alloy" {

    network {
      mode = "bridge"

      port "alloy" { to = 9080 }
    }

    ephemeral_disk {
      migrate = true
    }

    service {
      name = "alloy"

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

      connect {
        sidecar_service {
          proxy { 
            config { }
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

//        privileged = true
      }

      env {
        TZ = "Europe/Berlin"
      }


/*

// 1. Clustering block — enables Alloy's built-in cluster mode
clustering {
  enabled = true

  // The address this node advertises to peers.
  // Use the container/host IP — avoid 0.0.0.0 here.
  advertise_address = "{{ env NOMAD_HOST_PORT_alloy }}"  // e.g. "192.168.0.22:23456"
}

// 2. Discover peer Alloy nodes registered in Consul
discovery.consul "alloy_peers" {
  server = "http://consul.service.consul:8500"

  // The Consul service name under which Alloy nodes are registered
  service = "alloy"

  // Uncomment if Consul ACLs are enabled
  // token = env("CONSUL_TOKEN")
}

// 3. Re-label discovered peers to extract the clustering address
discovery.relabel "alloy_peers" {
  targets = discovery.consul.alloy_peers.targets

  // Use the Consul service address + port as the peer address.
  // Alloy clustering uses the same port as the HTTP listener (default 12345).
  rule {
    source_labels = ["__address__"]
    target_label  = "__address__"
    // If Consul returns host:port already, this is a no-op.
    // If only host is returned, append the port:
    replacement   = "$1:12345"
    regex         = "([^:]+)(?::\\d+)?"
  }
}

*/



      # Alloy configuration in River/Alloy DSL
      template {
        destination = "local/config.alloy"
        data        = <<EOT
// ============================================================
// Grafana Alloy — Consul-based peer discovery & clustering
// ============================================================

// COPY CLUSTERING HERE FROM ABOVE

// 4. Use discovered peers as cluster join addresses
// Pass them to the --cluster.join-addresses flag via env or command args.
// See docker-compose.yml for how to wire this up.

// ============================================================
// Example: distribute Nomad log scraping across cluster nodes
// ============================================================

discovery.consul "nomad" {
  server = "http://consul.service.consul:8500"

  // The Consul service name under which Nomad nodes are registered
  service = "nomad"
  tag     = "http"
}

discovery.relabel "nomad_logs" {
  targets = discovery.consul.nomad.targets

  rule {
    source_labels = ["__meta_nomad_alloc_desired_status"]
    regex         = "run"
    action        = "keep"
  }

  // general label for all container logs
  rule {
    target_label  = "type"
    replacement   = "container"
  }

  rule {
    source_labels = ["__meta_nomad_job_id"]
    target_label  = "application"
  }

  rule {
    source_labels = ["__meta_nomad_group_name"]
    target_label  = "group"
  }

  rule {
    source_labels = ["__meta_nomad_task_name"]
    target_label  = "task"
  }

  rule {
    source_labels = ["__meta_nomad_alloc_id"]
    target_label  = "alloc_id"
  }
}

// clustering = true tells Alloy to shard targets across cluster peers
// so each allocation is only scraped by one node
loki.source.file "nomad_stdout" {
  targets    = discovery.relabel.nomad_logs.output
  forward_to = [loki.write.default.receiver]

//  clustering {
//    enabled = true
//  }
}

// ============================================================
// Loki output
// ============================================================

loki.write "default" {
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