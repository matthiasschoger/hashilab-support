# Create Dynamic Host Volumes with 'nomad volume create' instead of 'register' like CSI volumes
type      = "host"
plugin_id = "mkdir"                    # Plugin automatically installed with > v1.10
name      = "alloy"
# Register host volume for all nodes which should provide that volume. This is per Nomad instance. Run 'nomad volume create' for each instance seperately
node_id   = "enter-your-node-ids-here" 

capability {
  access_mode     = "single-node-writer"
  attachment_mode = "file-system"
}
