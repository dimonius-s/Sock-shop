resource "yandex_vpc_network" "sockshop_network" {
  name = "sockshop-network"
}

resource "yandex_vpc_subnet" "sockshop_subnet" {
  name           = "sockshop-subnet"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.sockshop_network.id
  v4_cidr_blocks = ["10.0.0.0/24"]
}

resource "yandex_compute_instance" "swarm_manager" {
  # Конфигурация менеджера
  name = "swarm-manager"

  resources {
    cores  = 2
    memory = 4
  }

  boot_disk {
    initialize_params {
      image_id = "fd874d4jo8jbroqs6d7i"
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.sockshop_subnet.id
    nat       = true
  }

  metadata = {
    ssh-keys = "ubuntu:${file(var.public_key_path)}"
  }

  connection {
    type        = "ssh"
    host        = self.network_interface.0.nat_ip_address
    user        = "ubuntu"
    private_key = file(var.private_key_path)
  }

  provisioner "file" {
    source      = "docker-compose.yml"
    destination = "/home/ubuntu/docker-compose.yml"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y docker.io",
      "sudo systemctl start docker",
      "SWARM_MANAGER_IP=$(hostname -I | awk '{print $1}')",
      "JOIN_COMMAND=$(sudo docker swarm init --advertise-addr $SWARM_MANAGER_IP | grep SWMTKN)",
      "echo $JOIN_COMMAND > /home/ubuntu/join_command.sh"
    ]
  }
}

resource "yandex_compute_instance" "swarm_worker" {
  count      = 2
  depends_on = [yandex_compute_instance.swarm_manager]

  name = "swarm-node-${count.index}"

  resources {
    cores  = 2
    memory = 4
  }

  boot_disk {
    initialize_params {
      image_id = "fd874d4jo8jbroqs6d7i"
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.sockshop_subnet.id
    nat       = true
  }

  metadata = {
    ssh-keys = "ubuntu:${file(var.public_key_path)}"
  }

  connection {
    type        = "ssh"
    host        = self.network_interface.0.nat_ip_address
    user        = "ubuntu"
    private_key = file(var.private_key_path)
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y docker.io",
      "sudo systemctl start docker",
      "scp -o StrictHostKeyChecking=no ubuntu@${yandex_compute_instance.swarm_manager.network_interface.0.nat_ip_address}:/home/ubuntu/join_command.sh /home/ubuntu/join_command.sh",
      "sudo bash /home/ubuntu/join_command.sh"
    ]
  }
}

resource "null_resource" "swarm_deploy" {
  depends_on = [yandex_compute_instance.swarm_worker]

  provisioner "remote-exec" {
    inline = [
      "sudo docker stack deploy --compose-file docker-compose.yml socks-shop",
      "sudo docker service scale socks-shop_front-end=2",
    ]

    connection {
      type        = "ssh"
      host        = yandex_compute_instance.swarm_manager.network_interface.0.nat_ip_address
      user        = "ubuntu"
      private_key = file(var.private_key_path)
    }
  }
}