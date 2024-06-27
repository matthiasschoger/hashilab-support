job "loki" {
  datacenters = ["home"]
  type        = "service"

  group "loki" {

    constraint {
      attribute = "${node.class}"
      value     = "compute"
    }

    ephemeral_disk {
      # Used to store index, cache, WAL
      # Nomad will try to preserve the disk between job updates
      size    = 1000 # 1 GB
      migrate = true
    }

    network {
      mode = "bridge"

      port "rsyslog" { static = 514 }

      port "envoy_metrics_loki" { to = 9102 }
      port "envoy_metrics_syslog" { to = 9103 }
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

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=true",
        "traefik.http.routers.loki.rule=Host(`loki.lab.home`)",
        "traefik.http.routers.loki.entrypoints=websecure"
      ]

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics_loki}" # make envoy metrics port available in Consul
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
            memory = 64
          }
        }
      }
    }
/*
    service {
      name = "rsyslog"

      port = "rsyslog"

      task = "rsyslog"
    }
*/
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
        data        = file("config.yml")
        destination = "local/config.yml"
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
/*
    task "promtail" {
      driver = "docker"

      config {
        image = "grafana/promtail:latest"

        args = ["--config.file", "/local/promtail.yaml"]
      }

      env {
        TZ = "Europe/Berlin"
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
  - job_name: syslog 
    syslog: 
      listen_address: 0.0.0.0:1514 
      labels: 
        job: syslog 
    relabel_configs: 
      - source_labels: [__syslog_message_hostname] 
        target_label: host 
      - source_labels: [__syslog_message_hostname] 
        target_label: hostname 
      - source_labels: [__syslog_message_severity] 
        target_label: level 
      - source_labels: [__syslog_message_app_name] 
        target_label: application 
      - source_labels: [__syslog_message_facility] 
        target_label: facility 
      - source_labels: [__syslog_connection_hostname] 
        target_label: connection_hostname
EOH
      }

      resources {
        memory = 96
        cpu    = 50
      }
    }

    task "rsyslog" {
      driver = "docker"

      config {
        image = "linuxserver/syslog-ng:latest"
      }

      env {
        TZ = "Europe/Berlin"
      }

      template {
        destination = "/etc/syslog-ng/syslog-ng.conf"
        data            = <<EOH
source s_network {
    default-network-drivers(
    );
};

destination d_loki {
    syslog("promtail" transport("tcp") port("1514"));
};

log {
        source(s_network);
        destination(d_loki);
};
EOH
      }

      resources {
        memory = 96
        cpu    = 50
      }
    }
*/
    volume "loki" {
      type            = "csi"
      source          = "loki"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }
  }
}