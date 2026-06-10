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
      "echo 'DPkg::Lock::Timeout \"600\";' | sudo tee /etc/apt/apt.conf.d/99timeout"
    ]
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
      "chmod +x /opt/rivendell-install.sh",
      "/opt/rivendell-install.sh --phase1"
    ]
  }

  provisioner "shell" {
    expect_disconnect = true
    inline            = ["reboot"]
  }

  provisioner "shell" {
    pause_before = "45s"
    inline = [
      "sudo -u rd -H bash -c '/opt/rivendell-install.sh --phase2'"
    ]
  }

  provisioner "shell" {
    inline = [
      "rm -rf /opt/rivendell-install.sh /opt/APPS",
      "rm -f /root/.ssh/authorized_keys",
      "history -c"
    ]
  }
}
