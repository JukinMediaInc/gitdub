sudo rm -rf /usr/local/bin/gitdub
sudo ln -s $(pwd)/gitdub.rb /usr/local/bin/gitdub
sudo rm -rf /etc/init.d/gitdub
sudo ln -s $(pwd)/gitdub-initd /etc/init.d/gitdub
