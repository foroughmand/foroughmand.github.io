# frozen_string_literal: true

require "jekyll"

module Jekyll
  module Archives
    class Archive < Jekyll::Page
      attr_accessor :posts, :type, :slug

      # Attributes for Liquid templates
      ATTRIBUTES_FOR_LIQUID = %w(
        posts
        type
        title
        date
        name
        path
        url
        permalink
      ).freeze

      # Initialize a new Archive page
      #
      # site  - The Site object.
      # title - The name of the tag/category or a Hash of the year/month/day in case of date.
      #           e.g. { :year => 2014, :month => 08 } or "my-category" or "my-tag".
      # type  - The type of archive. Can be one of "year", "month", "day", "category", or "tag"
      # posts - The array of posts that belong in this archive.
      def initialize(site, title, type, posts)
        @site   = site
        @posts  = posts
        @type   = type
        @title  = title
        @config = site.config["jekyll-archives"]
        @slug   = slugify_string_title

        # Use ".html" for file extension and url for path
        @ext  = File.extname(relative_path)
        @path = relative_path
        @name = File.basename(relative_path, @ext)

        @data = {
          "layout" => layout,
        }
        @content = ""
      end

      # The template of the permalink.
      #
      # Returns the template String.
      def template
        @config.dig("permalinks", type)
      end

      # The layout to use for rendering
      #
      # Returns the layout as a String
      def layout
        @config.dig("layouts", type) || @config["layout"]
      end

      # Returns a hash of URL placeholder names (as symbols) mapping to the
      # desired placeholder replacements. For details see "url.rb".
      def url_placeholders
        if @title.is_a? Hash
          @title.merge(:type => @type)
        else
          { :name => @slug, :type => @type }
        end
      end

      # The generated relative url of this page. e.g. /about.html.
      #
      # Returns the String url.
      def url
        @url ||= URL.new(
          :template     => template,
          :placeholders => url_placeholders,
          :permalink    => nil
        ).to_s
      rescue ArgumentError
        raise ArgumentError, "Template \"#{template}\" provided is invalid."
      end

      def permalink
        data&.is_a?(Hash) && data["permalink"]
      end

      # Produce a title object suitable for Liquid based on type of archive.
      #
      # Returns a String (for tag and category archives) and nil for
      # date-based archives.
      def title
        @title if @title.is_a? String
      end

      # Produce a date object if a date-based archive
      #
      # Returns a Date.
      def date
        return unless @title.is_a?(Hash)

        @date ||= begin
          args = @title.values.map(&:to_i)
          Date.new(*args)
        end
      end

      # Obtain the write path relative to the destination directory
      #
      # Returns the destination relative path String.
      def relative_path
        @relative_path ||= begin
          path = URL.unescape_path(url).gsub(%r!^/!, "")
          path = File.join(path, "index.html") if url.end_with?("/")
          path
        end
      end

      # Returns the object as a debug String.
      def inspect
        "#<Jekyll:Archive @type=#{@type} @title=#{@title} @data=#{@data.inspect}>"
      end

      # The Liquid representation of this page.
      def to_liquid
        @to_liquid ||= Jekyll::Archives::PageDrop.new(self)
      end

      private

      # Generate slug if @title attribute is a string.
      #
      # Note: mode other than those expected by Jekyll returns the given string after
      # downcasing it.
      def slugify_string_title
        return unless title.is_a?(String)

        Utils.slugify(title, :mode => @config["slug_mode"])
      end
    end
  end
end

module Jekyll
  module Archives
    class PageDrop < Jekyll::Drops::Drop
      extend Forwardable

      mutable false

      def_delegators :@obj, :posts, :type, :title, :date, :name, :path, :url, :permalink
      private def_delegator :@obj, :data, :fallback_data
    end
  end
end

module Jekyll
  module Archives
    VERSION = "2.2.1"
  end
end

module Jekyll
  module Archives
    # Internal requires
    #autoload :Archive,  "jekyll-archives/archive"
    #autoload :PageDrop, "jekyll-archives/page_drop"
    #autoload :VERSION,  "jekyll-archives/version"

    class Archives < Jekyll::Generator
      safe true

      DEFAULTS = {
        "layout"     => "archive",
        "enabled"    => [],
        "permalinks" => {
          "year"     => "/:year/",
          "month"    => "/:year/:month/",
          "day"      => "/:year/:month/:day/",
          "tag"      => "/tag/:name/",
          "category" => "/category/:name/",
        },
      }.freeze

      def initialize(config = {})
        archives_config = config.fetch("jekyll-archives", {})
        if archives_config.is_a?(Hash)
          @config = Utils.deep_merge_hashes(DEFAULTS, archives_config)
        else
          @config = nil
          Jekyll.logger.warn "Archives:", "Expected a hash but got #{archives_config.inspect}"
          Jekyll.logger.warn "", "Archives will not be generated for this site."
        end
        @enabled = @config && @config["enabled"]
      end

      def generate(site)
        return if @config.nil?

        @site = site
        @posts = site.posts
        @archives = []

        @site.config["jekyll-archives"] = @config

        read
        @site.pages.concat(@archives)

        @site.config["archives"] = @archives
      end

      # Read archive data from posts
      def read
        read_tags
        read_categories
        read_dates
      end

      def read_tags
        if enabled? "tags"
          tags.each do |title, posts|
            @archives << Archive.new(@site, title, "tag", posts)
          end
        end
      end

      def read_categories
        if enabled? "categories"
          categories.each do |title, posts|
            @archives << Archive.new(@site, title, "category", posts)
          end
        end
      end

      def read_dates
        years.each do |year, y_posts|
          append_enabled_date_type({ :year => year }, "year", y_posts)
          months(y_posts).each do |month, m_posts|
            append_enabled_date_type({ :year => year, :month => month }, "month", m_posts)
            days(m_posts).each do |day, d_posts|
              append_enabled_date_type({ :year => year, :month => month, :day => day }, "day", d_posts)
            end
          end
        end
      end

      # Checks if archive type is enabled in config
      def enabled?(archive)
        @enabled == true || @enabled == "all" || (@enabled.is_a?(Array) && @enabled.include?(archive))
      end

      def tags
        @site.tags
      end

      def categories
        @site.categories
      end

      # Custom `post_attr_hash` method for years
      def years
        date_attr_hash(@posts.docs, "%Y")
      end

      # Custom `post_attr_hash` method for months
      def months(year_posts)
        date_attr_hash(year_posts, "%m")
      end

      # Custom `post_attr_hash` method for days
      def days(month_posts)
        date_attr_hash(month_posts, "%d")
      end

      private

      # Initialize a new Archive page and append to base array if the associated date `type`
      # has been enabled by configuration.
      #
      # meta  - A Hash of the year / month / day as applicable for date.
      # type  - The type of date archive.
      # posts - The array of posts that belong in the date archive.
      def append_enabled_date_type(meta, type, posts)
        @archives << Archive.new(@site, meta, type, posts) if enabled?(type)
      end

      # Custom `post_attr_hash` for date type archives.
      #
      # posts - Array of posts to be considered for archiving.
      # id    - String used to format post date via `Time.strptime` e.g. %Y, %m, etc.
      def date_attr_hash(posts, id)
        hash = Hash.new { |hsh, key| hsh[key] = [] }
        posts.each { |post| hash[post.date.strftime(id)] << post }
        hash.each_value { |posts| posts.sort!.reverse! }
        hash
      end
    end
  end
end
