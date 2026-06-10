packer {
  required_plugins {
    digitalocean = {
      version = ">= 1.0.4"
      source  = "github.com/hashicorp/digitalocean"
    }
  }
}

variable "do_api_token" {
  type    = string
  default = "${env("DIGITALOCEAN_TOKEN")}"
}

source "digitalocean" "rivendell_golden" {
  api_token     = var.do_api_token
  image         = "ubuntu-24-04-x64" # Standard AMD64 for Universal compatibility
  region        = "nyc3"             
  size          = "s-2vcpu-4gb"      # Compilation requires a bit of horsepower
  ssh_username  = "root"
  snapshot_name = "rivendell-4.4.1-custom-mp3-{{timestamp}}"
}

build {
  sources = ["source.digitalocean.rivendell_golden"]

  provisioner "shell" {
    inline = [
      "mkdir -p /opt/APPS",
      "cloud-init status --wait || true",
      "sudo systemctl disable --now apt-daily.timer apt-daily-upgrade.timer unattended-upgrades || true",
      "echo "DPkg::Lock::Timeout \"600\";" | sudo tee /etc/apt/apt.conf.d/99timeout",
    ]
  }
  }

  provisioner "file" {
    source      = "./rivendell-auto-install.sh"
    destination = "/opt/rivendell-install.sh"
  }

  provisioner "file" {
    source      = "./APPS/"
    destination = "/opt/APPS/"
  }

  provisioner "shell" {
    inline = [
      "mkdir -p /opt/APPS",
      "cloud-init status --wait || true",
      "sudo systemctl disable --now apt-daily.timer apt-daily-upgrade.timer unattended-upgrades || true",
      "echo "DPkg::Lock::Timeout \"600\";" | sudo tee /etc/apt/apt.conf.d/99timeout",
    ]
  }
  }

  provisioner "shell" {
    inline = [
      "mkdir -p /opt/APPS",
      "cloud-init status --wait || true",
      "sudo systemctl disable --now apt-daily.timer apt-daily-upgrade.timer unattended-upgrades || true",
      "echo "DPkg::Lock::Timeout \"600\";" | sudo tee /etc/apt/apt.conf.d/99timeout",
    ]
  }
  }

  provisioner "shell" {
    inline = [
      "mkdir -p /opt/APPS",
      "cloud-init status --wait || true",
      "sudo systemctl disable --now apt-daily.timer apt-daily-upgrade.timer unattended-upgrades || true",
      "echo "DPkg::Lock::Timeout \"600\";" | sudo tee /etc/apt/apt.conf.d/99timeout",
    ]
  }
  }

  provisioner "shell" {
    inline = [
      "mkdir -p /opt/APPS",
      "cloud-init status --wait || true",
      "sudo systemctl disable --now apt-daily.timer apt-daily-upgrade.timer unattended-upgrades || true",
      "echo "DPkg::Lock::Timeout \"600\";" | sudo tee /etc/apt/apt.conf.d/99timeout",
    ]
  }
  }
}
