# frozen_string_literal: true

require 'string-text'
require 'constrain'
include Constrain

require_relative "sqlsnip/version"


module Sqlsnip
  class Error < StandardError; end
  
  class Source
    UID_RE = /(?:[.\w]+)/
    TABLE_MODIFIERS_RE = /(?:global|local|temporary|temp|unlogged)/
    VIEW_MODIFIERS_RE = /(?:temp|temporary|recursive)/
    IF_NOT_EXISTS_RE = /(?:if\s+not\s+exists)/
    TRIGGER_MODIFIERS_RE = /(?:constraint)/

    FUNCTION_ARGMODE_RE = /(?:in|out|inout|variadic)/
    FUNCTION_ARGS_RE = /(?:#{FUNCTION_ARGMODE_RE}\s*,\s*)/
    FUNCTION_DEFAULT_RE = /(?:default\s+.*)/

    TABLE_RE = /(?:#{TABLE_MODIFIERS_RE}\s+)*table\s+(?:#{IF_NOT_EXISTS_RE}?\s+)?(#{UID_RE})/i
    VIEW_RE = /(?:#{VIEW_MODIFIERS_RE}\s+)*view\s+(#{UID_RE})/i
    FUNCTION_RE = /function\s+(#{UID_RE})\s*\((.*?)\)\s+(?:returns|$)/i
    PROCEDURE_RE = /function\s+(#{UID_RE})\s*\((.*?)\)\s+(?:as|$)/i
    TRIGGER_RE = /trigger\s+(#{UID_RE})\s+.*\s+on\s+(#{UID_RE})/i

    DEFAULT_VALUE_RE = /(?:[^,\(]+(?:\([^\)]*\))?)/
    DEFAULT_RE=/default\s+#{DEFAULT_VALUE_RE}/i

    SEARCH_PATH_RE = /^\s*set\s+search_path/

    # Source file
    attr_reader :file

    # Starting and ending line (inclusive). May be nil
    attr_reader :start_line, :stop_line

    # The selected range of lines as read from the file
    attr_reader :lines

    # Array of generated statements
    attr_reader :stmts 

    # Initial search path
    attr_reader :search_path

    def initialize(file, start_line = nil, stop_line = nil, search_path: nil)
      constrain file, String
      constrain start_line, Integer, nil
      constrain stop_line, Integer, nil
      constrain search_path, String, nil
      @file, @start_line, @stop_line = file, start_line, stop_line
      File.exist?(@file) or raise Error, "Can't find #{file}"
      @lines = []
      @stmts = nil
      @search_path = search_path
      if @search_path && !@search_path.empty?
        @search_path_stmt = "set search_path to #{@search_path};"
      end
      @project_dir = nil
    end

    def parse
      read_lines
      generate_drop_stmts
      self
    end

    def self.parse(*args, **opts) self.new(*args, **opts).parse end

    def generate(interactive: false)
      generate_search_path_stmt if @search_path != ""
      generate_interactive_stmts if interactive
      @stmts
    end

    def generate_drop_stmts
      @stmts = []
      for line in lines
        case line
          when /^\s*set\s+search_path/
            sql = line
          when /^\s*create\s+(.*)/
            object = $1
            case object 
              when TABLE_RE
                table = $1
                sql = "drop table if exists #{table} cascade;"
              when VIEW_RE
                view = $1
                sql = "drop view if exists #{view} cascade;"
              when FUNCTION_RE
                function = $1
                args_str = $2
                # We assume that default values contain no commas
                args = args_str.split(/\s*,\s*/).map { |arg|
                  arg.sub(/^#{UID_RE}\s+/, "").sub(/\s+#{FUNCTION_DEFAULT_RE}/, "") 
                }
                sql = "drop function if exists #{function}(#{args.join(', ')}) cascade;"
              when PROCEDURE_RE
                procedure, args_str = $1, $2
                # We assume that default values contain no commas
                args = args_str.split(/\s*,\s*/).map { |arg|
                  arg.sub(/^#{UID_RE}\s+/, "").sub(/\s+#{FUNCTION_DEFAULT_RE}/, "") 
                }
                sql = "drop procedure if exists #{procedure}(#{args.join(', ')}) cascade;"
              when TRIGGER_RE
                trigger, table = $1, $2
                sql = "drop trigger if exists #{trigger} on #{table} cascade;"
            else
              next
            end
        else
          next
        end
        @stmts << sql
      end
    end

    # Generate a 'set search_path' statement
    def generate_search_path_stmt
      if @search_path == ""
        return @stmts
      elsif @search_path_stmt
        @stmts.unshift @search_path_stmt
      else
        schema = find_schema_from_file(file)
        search_path = "set search_path to #{schema};"
        @stmts.unshift search_path
      end
    end

    def generate_interactive_stmts
      @stmts.unshift '\set ON_ERROR_STOP on'
    end


  private
    attr_reader :search_path_stmt, :project_dir

    def read_lines
      IO.readlines(file).each.with_index { |line, i|
        line.chomp!
        i += 1
        break if !stop_line.nil? && i > stop_line
        next if line =~ /^\s*$/
        if @lines.empty? && @search_path.nil? && line =~ /^\s*set\s+search_path/
          @search_path_stmt = line
        elsif !start_line.nil? && i < start_line
          ;
        elsif stop_line.nil? || i <= stop_line
          @lines << line
        end
      }
    end

    # Search upwards in the directory hierarchy for a prick project directory
    def find_project_dir(path)
      path = File.absolute_path(path)
      while !File.exist?(File.join(path, "prick.yml"))
        path != "/" or raise Error, "Can't find project directory"
        path = File.dirname(path)
      end
      path
    end
  
    # Use the prick source directory structure to find the schema name
    def find_schema_from_file(file)
      path = File.dirname(file)
      project_dir = find_project_dir(File.dirname(file))
      path = path.delete_prefix(project_dir)
      if path =~ /schema\/([^\/]+)/
        schema = $1
      else
        schema != "" or raise Error, "Can't find schema from #{file}"
      end
      schema
    end
  end
end
