gitdub
======

**gitdub** is a [github web-hook][post-receive-hook] that converts a
changeset pushed into one email per change via [git-notifier][git-notifier].
Unlike the existing github email hook, gitdub sends out detailed diffs for each
change.

Setup
=====

### Dependencies

  - Ruby 1.9
  - `gem install git sinatra`
  - [git-notifier][git-notifier]

### Installation
  
  1. `cp gitdub /path/to/dir/in/$PATH`
  2. `cp config.yml.example config.yml`
  3. `gitdub config.yml`

### Integration with github

  1. Navigate to a repository you own, e.g., `https://github.com/user/repo`
  2. Click on *Settings* on the top-right corner
  3. Click on *Service Hooks* in the left sidebar
  4. Select the first service called *WebHook URLs*
  5. Enter the URL to reach gitdub, e.g., `http://gitdub.mydomain.com:8888/`
  6. Click *Test Hook* to let github initialize the repository
  7. Click *Update Settings* to save your changes

Customizing
===========

The [YAML](http://www.yaml.org) configuration file contains the list of
repositories that gitdub tracks. It consists of three major sections: *(i)*
`gitdub` for global parameters, *(ii)* `notifier` for options related to
git-notifier, and *(iii)* `github` to configure the github repositories to
track.

The first section `gitdub` specifies global options, such as the interfaces
gitdub should bind to and ports to listen on. The second section describes the
behavior of git-notifier, e.g., the sender of the email (`from:`), the
receivers (`to:`), and the prefix of the email subject (`subject:`). The thrid
section `gitdub` contains a list of repository entries, where each entry must
at least contain an `id` field. If an item does not contain any further
options, the globals from the `notifier` section apply. However, in most cases
it makes sense to override these globals with repository-specific information,
e.g.:

    notifier:
      # The email sender. (Can be overriden for each repository.)
      from: 'Sam Sender <foo@host.com>'

      # The email subject prefix. (Can be overriden for each repository.)
      subject: '[git]'

    github:
      - id: mavam/gitdub
        subject: '[foo]'           # Override global '[git]' subject prefix.
        from: [vallentin@icir.org] # Overrides global sender.

      - id: mavam/.*
        from: mavam                # Overrides global sender.

Note the regular expression in the second entry. This enables the configuration
of entire sets of repositories. Since gitdub processes the list sequentially in
order of definition, the settings of the first match apply. For example, a
subsequent entry for `mavam/foo` would never match.

### Restricting Access

To prevent unauthorized access to the service, you can restrict the set of
allowed source IP addresses to github addresses, e.g., via iptables:

    iptables -A INPUT -m state --state NEW -m tcp -p tcp \
        -s 207.97.227.253,50.57.128.197,108.171.174.17 --dport 42042 -j ACCEPT

If that's not an option on your machine, you can also perform application-layer
filtering in gitdub by setting the following configuration option:

    allowed_sources: [207.97.227.253, 50.57.128.197, 108.171.174.17]


Licence
=======

Gitdub comes with a BSD license, please see COPYING for details.

[git-notifier]: http://www.icir.org/robin/git-notifier
[sinatra]: http://www.sinatrarb.com
[post-receive-hook]: https://help.github.com/articles/post-receive-hooks
