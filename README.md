Rackspace CloudFiles Jekyll Plugin
=

This Jekyll plugin adds the Liquid tag "cloud_files". Use it to automatically
upload static files (JS, CSS and images) to a Rackspace CloudFiles container,
rewriting the URLs as it goes.

REQUIREMENTS
-

* Requires the cloudfiles gem: sudo gem install cloudfiles

INSTALLATION
-

Create a directory called _plugins in your Jekyll project if you don't already
have one, and put .rb file in there.

USAGE AND CONFIGURATION
-

Example: &lt;link rel="stylesheet" href="{% cloud_files /i/style.css %}" type="text/css" /&gt;

All URLs specified must be absolute paths (i.e. start with a / where / refers
to the Jekyll source dir). This ensures that when the plugin is disabled the
site generated will still work but with local URLs.

The names of the uploaded files are the SHA1 hash of the file contents. This
means files are only uploaded (and therefore downloaded) once, minimising
space and bandwidth usage. It also means that there are no caching issues
when you upload changed files.

The following options can be set in _config.yml...

    cloud_files:
      # REQUIRED Enabled must be set to true, otherwise the plugin does nothing
      enabled: true
      # REQUIRED (see note below) Your Rackspace CloudFiles username and API key
      username: your_username
      api_key: your_api_key
      # The datacentre your account is in. Defaults to 'us'.
      datacentre: uk
      # The destination container name- it will be created if it does not exist
      container: static.domain.com
      # Optional CNAME - gets used in place of the container's CDN URL
      cname: http://static.domain.com/
      # Optional prefix for uploaded files
      upload_prefix: www/
      # Force all files to be uploaded even if they already exist - this should
      # never be necessary, but I needed it during development so I've left it
      # in :)
      force_upload: false

NOTE: The username and api_key options can be placed in ~/.rackspacecloudfiles
so that you can still publish your Jekyll source but keep your credentials
private.

TODO
-

* CSS and JS files are not currently processed - I'm still trying to work out
  the best way to enable this.

* The plugin does not currently clean up unused files in the container,
  mainly because I couldn't find a way to run something when Jekyll has
  finished generating the site. The code is there to do it (the function is
  RSF.instance.delete_unused_objects()) but it's untested.

If you have any suggestions on these or anything else, please let me know.

This plugin lives on GitHub: https://github.com/3ft9/jekyll-rackspacecloudfiles