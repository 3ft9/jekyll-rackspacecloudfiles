# This Jekyll plugin adds the Liquid tag "cloud_files". Use it to automatically
# upload static files (JS, CSS and images) to a Rackspace CloudFiles container,
# rewriting the URLs as it goes.
#
# USAGE
#
# <link rel="stylesheet" href="{% cloud_files /i/style.css %}" type="text/css">
#
# REQUIREMENTS
#
# * Requires the cloudfiles gem: sudo gem install cloudfiles
#
# USAGE AND CONFIGURATION
#
# All URLs specified must be absolute paths (i.e. start with a / where / refers
# to the Jekyll source dir). This ensures that when the plugin is disabled the
# site generated will still work but with local URLs.
#
# The names of the uploaded files are the SHA1 hash of the file contents. This
# means files are only uploaded (and therefore downloaded) once, minimising
# space and bandwidth usage. It also means that there are no caching issues
# when you upload changed files.
#
# The following options can be set in _config.yml...
#
# cloud_files:
#   # REQUIRED Enabled must be set to true, otherwise the plugin does nothing
#   enabled: true
#   # REQUIRED (see note below) Your Rackspace CloudFiles username and API key
#   username: your_username
#   api_key: your_api_key
#   # The datacentre your account is in. Defaults to 'us'.
#   datacentre: uk
#   # The destination container name- it will be created if it does not exist
#   container: static.domain.com
#   # Optional CNAME - gets used in place of the container's CDN URL
#   cname: http://static.domain.com/
#   # Optional prefix for uploaded files
#   upload_prefix: www/
#   # Force all files to be uploaded even if they already exist - this should
#   # never be necessary, but I needed it during development so I've left it
#   # in :)
#   force_upload: false
#
# NOTE: The username / api_key options can be placed in ~/.rackspacecloudfiles
# so that you can still publish your Jekyll source but keep your credentials
# private.
#
# TODO:
#
# * CSS and JS files are not currently processed - I'm still trying to work out
#   the best way to enable this.
#
# * The plugin does not currently clean up unused files in the container,
#   mainly because I couldn't find a way to run something when Jekyll has
#   finished generating the site. The code is there to do it (the function is
#   RSF.instance.delete_unused_objects()) but it's untested.
#
# If you have any suggestions on these or anything else, please let me know.
#

require 'singleton'
require 'digest/sha1'
require 'rubygems'
require 'cloudfiles'

module Jekyll
	RACKSPACECLOUDFILES_CREDENTIALS_FILENAME = '~/.rackspacecloudfiles'

	# RackspaceCloudFiles implements the tag
	class RackspaceCloudFiles < Liquid::Tag
		def initialize(tag_name, text, tokens)
			super
			# Grab the full text and call it the filename
			@filename = text.strip
		end

		def render(context)
			# Only initialise the singleton helper class once
			if !RSF.instance.initialised
				RSF.instance.init(context.registers[:site].config['cloud_files'])
			end

			# If the plugin is enabled...
			if RSF.instance.enabled
				# ...tell the helper class to upload the file
				RSF.instance.upload_file @filename
			else
				# Otherwise simply return the string that came in
				@filename
			end
		end
	end

	# RSF is a singleton object that implements the uploading functionality. It
	# maintains a cache of the files that have already been uploaded to prevent
	# them being uploaded more than once. Note that this caching works by the
	# file contents, not the filenames.
	class RSF
		include Singleton

		attr_reader :enabled, :initialised

		def initialize
			@enabled = false
			@initialised = false
			@files = {}
		end

		# This should only be called once and expects a hash of the configuration
		# options
		def init(config)
			# Set the enabled attribute for easy reference
			@enabled = config['enabled']
			if @enabled
				# Work out the full base path for the project
				@base_path	= File.expand_path(File.join(File.dirname(__FILE__), '..'))

				# Get the username and api_key from the config
				@username = config['username']
				@api_key = config['api_key']

				# If either of them were missing...
				if @username.nil? or @api_key.nil?
					# ...attempt to load from ~/.rackspacecloudfiles
					if File.exists?(File.expand_path(RACKSPACECLOUDFILES_CREDENTIALS_FILENAME))
						credentials = YAML.load_file(File.expand_path(RACKSPACECLOUDFILES_CREDENTIALS_FILENAME))
						@username = credentials['username']
						@api_key = credentials['api_key']
					end

					# If either of them are still missing, raise an error
					if @username.nil? or @api_key.nil?
						raise "You must provide your RackspaceCloud username."
					end
				end

				# Grab the correct constant for the configured datacentre
				@datacentre = config['datacentre']
				if @datacentre.nil? or @datacentre.downcase == 'us'
					@datacentre = CloudFiles::AUTH_US
				elsif @datacentre.downcase == 'uk'
					@datacentre = CloudFiles::AUTH_UK
				else
					raise "The datacentre must be either us or uk."
				end

				# Make sure we have a destination container
				@container = config['container']
				if @container.nil?
					raise "You must specify a destination container."
				end

				# Get the upload prefix, or set the default
				@upload_prefix = config['upload_prefix']
				if @upload_prefix.nil?
					@upload_prefix = ""
				end

				# Connect to the CloudFiles service
				@cf = CloudFiles::Connection.new(:username => @username, :api_key => @api_key, :auth_url => @datacentre)
				# If the container already exists...
				if @cf.container_exists?(@container)
					# ...fetch it
					@cfc = @cf.container(@container)
				else
					# Otherwise create it and make it public (i.e. publish it to the CDN)
					@cfc = @cf.create_container(@container)
					@cfc.make_public()
				end

				# If we don't have a cname configured, get the CDN URL for the container
				@cname = config['cname']
				if @cname.nil?
					@cname = @cfc.cdn_url + "/"
				end

				# Find out whether we're uploading all files, regardless of whether they already exist
				@force_upload = config['force_upload']

				# Set an attribute to make sure we don't do this again
				@initialised = true
			end
		end

		# Process an individual file
		def upload_file(fn)
			# Check the filename is valid
			if fn[0..0] != "/"
				raise "All URLs must begin with a /."
			end

			# Calculate the full path to the file
			fn = File.join(@base_path, fn[1..-1])

			# Check that we haven't seen this file yet
			if !@files.has_key?(fn)
				# Make sure it exists
				if !File.exists?(fn)
					raise "File {" + fn + "} not found!"
				end

				# Get the SHA1 hash of the file
				sha1 = Digest::SHA1.new
				open(fn, "r") do |io|
					counter = 0
					while (!io.eof)
						sha1.update(io.readpartial(16384))
					end
				end
				# And use it as the filename, but take the extension from the source file
				obj_name = @upload_prefix + sha1.hexdigest + File.extname(fn)

				# Check to see if we've had this file's contents before
				if !@files.has_key?(obj_name)
					# Check to see if the object already exists
					if @force_upload or !@cfc.object_exists?(obj_name)
						# Upload the file
						puts 'RackspaceCloudFiles: Uploading ' + obj_name
						@cfc.create_object(obj_name, false).write(open(fn, "r"))
					end

					# If we're forcing an upload, also purge the file from the CDN
					if @force_upload
						@cfc.purge_from_cdn
					end

					@files[fn] = @files[obj_name] = @cname + obj_name
				end
			end

			@files[fn]
		end

		# UNTESTED Delete any files in the container matching the prefix that
		# haven't been seen by the plugin.
		def delete_unused_objects()
			@cfc.objects({ :prefix => @upload_prefix }).each do |obj|
				if !@files.has_value?(obj)
					@cfc.delete_object(obj)
				end
			end
		end
	end
end

Liquid::Template.register_tag('cloud_files', Jekyll::RackspaceCloudFiles)
