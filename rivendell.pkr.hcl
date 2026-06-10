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
  image         = "ubuntu-26-04-x64" # Standard AMD64 for Universal compatibility
  region        = "nyc3"             
  size          = "s-2vcpu-4gb"      # Compilation requires a bit of horsepower
  ssh_username  = "root"
  snapshot_name = "rivendell-4.4.1-custom-mp3-{{timestamp}}"
}

build {
  sources = ["source.digitalocean.rivendell_golden"]

  provisioner "file" {
    source      = "./rivendell-auto-install.sh"
    destination = "/tmp/rivendell-install.sh"
  }

  provisioner "file" {
    source      = "./APPS/"
    destination = "/tmp/APPS/"
  }

  provisioner "shell" {
    inline = [
      "chmod +x /tmp/rivendell-install.sh",
      "/tmp/rivendell-install.sh --phase1"
    ]
  }

  provisioner "shell" {
    expect_disconnect = true
    inline            = ["reboot"]
  }

  provisioner "shell" {
    pause_before = "30s"
    inline = [
      "sudo -u rd -H bash -c '/tmp/rivendell-install.sh --phase2'"
    ]
  }

  provisioner "shell" {
    inline = [
      "rm -rf /tmp/rivendell-install.sh /tmp/APPS",
      "rm -f /root/.ssh/authorized_keys",
      "history -c"
    ]
  }
}
