Vagrant.configure("2") do |config|
  config.vm.define "Elastic" do |elastic|
    elastic.vm.box = "bento/centos-7"
    elastic.vm.hostname = 'elastic-8-sec'
    elastic.vm.box_url = "bento/centos-7"
    elastic.vm.provision :shell, path: "ESBootstrap.sh"
    elastic.vm.network :private_network, ip:"10.0.0.10"
    elastic.vm.network :forwarded_port, guest: 5601, host: 5601, host_ip: "0.0.0.0", id: "kibana", auto_correct: true
    elastic.vm.network :forwarded_port, guest: 8888, host: 8888, host_ip: "0.0.0.0", id: "caldera", auto_correct: true
    elastic.vm.provider :virtualbox do |v|
      v.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      v.customize ["modifyvm", :id, "--cpus", 4]
      v.customize ["modifyvm", :id, "--memory", 8192]
      v.customize ["modifyvm", :id, "--name", "elastic-8-sec"]
    end
  end
  config.vm.define "Linux" do |linux|
    linux.vm.box = "bento/centos-7"
    linux.vm.hostname = 'linux-agent-8'
    linux.vm.box_url = "bento/centos-7"
    linux.vm.provision :shell, path: "ALBootstrap.sh"
    linux.vm.network :private_network, ip: "10.0.0.20"
    linux.vm.provider :virtualbox do |v|
      v.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      v.customize ["modifyvm", :id, "--cpus", 1]
      v.customize ["modifyvm", :id, "--memory", 1024]
      v.customize ["modifyvm", :id, "--name", "linux-agent-8"]
    end
  end
  config.vm.define "Windows" do |windows|
    windows.vm.box = "gusztavvargadr/windows-10-21h2-enterprise"
    windows.vm.box_version = "2102.0.2202"
    windows.vm.hostname = 'windows-agent-8'
    windows.vm.box_url = "gusztavvargadr/windows-10-21h2-enterprise"
    windows.vm.provision :shell, privileged: "true", path: "AWBootstrap.ps1"
    windows.vm.network :private_network, ip: "10.0.0.30"
    windows.vm.provider :virtualbox do |v|
	  v.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      v.customize ["modifyvm", :id, "--cpus", 2]
      v.customize ["modifyvm", :id, "--memory", 4096]
      v.customize ["modifyvm", :id, "--name", "windows-agent-8"]
      v.customize ["modifyvm", :id, "--nested-hw-virt", "off"]
    end
  end
end