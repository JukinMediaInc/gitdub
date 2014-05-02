#!/bin/bash

# assumes user uses .bashrc and is centos -based
set -ex

# INSTALL rbenv and bundler
git clone https://github.com/sstephenson/rbenv.git ~/.rbenv
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bash_profile
echo 'eval "$(rbenv init -)"' >> ~/.bash_profile
type rbenv
rbenv rehash
rbenv versions
git clone https://github.com/sstephenson/ruby-build.git ~/.rbenv/plugins/ruby-build
rbenv install -l
rbenv install 2.1.1
cd ~/.rbenv/plugins
git clone git://github.com/jamis/rbenv-gemset.git
cd ~
rbenv rehash
rbenv gemset create 2.1.1 gitdub
rbenv gemset active
rbenv gemset list

cd ~/git/JukinMediaInc/gitdub
gem install bundler
bundle install --path vendor

# INSTALL pyenv, python, pygithub
sudo yum install -y  gcc gcc-c++ make git patch openssl-devel zlib-devel readline-devel sqlite-devel bzip2-devel
git clone git://github.com/yyuu/pyenv.git ~/.pyenv

export PATH="$HOME/.pyenv/bin:$PATH"
eval "$(pyenv init - bash)"

cat << _PYENVCONF_ >> ~/.bashrc
export PATH="$HOME/.pyenv/bin:$PATH"
eval "$(pyenv init - bash)"
_PYENVCONF_

pyenv install 2.7.6
pyenv versions

pyenv shell 2.7.6
pyenv global 2.7.6
pyenv versions
pyenv rehash

mkdir -p ~/git
cd ~/git

git clone git://git.icir.org/git-notifier
cd git-notifier
sudo rm /usr/local/bin/git-notifier
sudo ln -s ~jenkins/git/git-notifier/git-notifier /usr/local/bin/.
sudo rm /usr/local/bin/github-notifier
sudo ln -s ~jenkins/git/git-notifier/github-notifier /usr/local/bin/.

cd ~/git
git clone git://github.com/JukinMediaInc/gitdub.git gitdub-jukin
cd gitdub-jukin
sudo rm -rf /usr/local/bin/gitdub
sudo ln -s ~jenkins/git/gitdub-jukin/gitdub.rb /usr/local/bin/gitdub
sudo ln -s ~jenkins/git/gitdub-jukin/gitdub-initd /etc/init.d/gitdub
echo "Please copy config-example.yml to /etc/gitdub-config.yml and customize, then '/etc/init.d/gitdub start'"


