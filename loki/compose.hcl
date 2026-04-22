job "loki" {
  datacenters = ["home"]
  type        = "service"

  group "loki" {

    ephemeral_disk {
      # Used to store index, cache, WAL
      # Nomad will try to preserve the disk between job updates
      size    = 1000 # 1 GB
      migrate = true
    }

    network {
      mode = "bridge"

      port "envoy_metrics_loki" { to = 9102 }
    }

    service {
      name = "loki"

      port = 3100

      check {
        type     = "http"
        path     = "/ready"
        interval = "10s"
        timeout  = "2s"
        expose   = true # required for Connect
      }

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics_loki}" # make envoy metrics port available in Consul
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
            memory = 64
          }
        }
      }
    }

    task "server" {
      driver = "docker"

      user = "1026:100" # matthias:users

      config {
        image = "grafana/loki:latest"

        args = [
          "-config.file=/local/config.yml",
          "-config.expand-env=true",
        ]
      }

      env {
        TZ = "Europe/Berlin"
      }

      template {
        destination = "local/config.yml"
        data        = <<EOT
auth_enabled: false

server:
  log_level: warn
  http_listen_port: 3100

common:
  replication_factor: 1
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: inmemory
  path_prefix: {{ env "NOMAD_ALLOC_DIR" }}/data/tmp

ingester:
  lifecycler:
    address: 127.0.0.1
    final_sleep: 0s
  # Any chunk not receiving new logs in this time will be flushed
  chunk_idle_period: 1h
  # All chunks will be flushed when they hit this age, default is 1h
  max_chunk_age: 1h
  # Loki will attempt to build chunks up to 1.5MB, flushing if chunk_idle_period or max_chunk_age is reached first
  chunk_target_size: 1048576
  wal:
    dir: {{ env "NOMAD_ALLOC_DIR" }}/data/wal
    flush_on_shutdown: true
    replay_memory_ceiling: "800M"

compactor:
  working_directory: {{ env "NOMAD_ALLOC_DIR" }}/data/tsdb-shipper-compactor

schema_config:
  configs:
    - from: 2025-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: tsdb_index_
        period: 24h

storage_config:
  filesystem:
    directory: /loki/chunks
  tsdb_shipper:
    active_index_directory: {{ env "NOMAD_ALLOC_DIR" }}/data/tsdb-shipper-active
    cache_location: {{ env "NOMAD_ALLOC_DIR" }}/data/tsdb-shipper-cache
    cache_ttl: 24h         # Can be increased for faster performance over longer query periods, uses more disk space

limits_config:
  reject_old_samples: true
  reject_old_samples_max_age: 168h

chunk_store_config:
#  max_look_back_period: 0s
  chunk_cache_config:
    embedded_cache:
      enabled: true
      max_size_mb: 1000
      ttl: 24h

query_range:
  parallelise_shardable_queries: false # helps with "context canceled" messages I'm getting
EOT
      }

      resources {
        memory = 500
        cpu    = 100
      }

      volume_mount {
        volume      = "loki"
        destination = "/loki"
      }    
    }

    volume "loki" {
      type            = "csi"
      source          = "loki"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }
  }
}