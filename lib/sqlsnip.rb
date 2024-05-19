# frozen_string_literal: true

require_relative "sqlsnip/version"

module Sqlsnip
  class Error < StandardError; end
  
  class Prg
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

    attr_reader :file, :start_line, :stop_line
    attr_reader :lines # The selected range of lines

    def initialize(file, start_line, stop_line)
      @file, @start_line, @stop_line = file, start_line, stop_line
      File.exist?(@file) or raise Error, "Can't find #{file}"
      @lines = []
      @initial_search_path = nil
      @project_dir = nil
    end

    def run
      read_lines
      stmts, has_search_path = generate_drop_statements
      if !has_search_path
        search_path = @initial_search_path
        if search_path.nil?
          schema = find_schema_from_file(file)
          search_path = "set search_path to #{schema}"
        end
        stmts.unshift search_path
      end

      puts '\set ON_ERROR_STOP on'
      puts stmts
      puts
      puts lines
    end

  private
    attr_reader :initial_search_path, :project_dir

    def read_lines
      IO.readlines(file).each.with_index { |line, i|
        i += 1
        if i < start_line
          @initial_search_path = line if line =~ /^\s*set\s+search_path/
        elsif i <= stop_line
          lines << line
        else
          break
        end
      }
    end

    def find_project_dir(path)
      path = File.absolute_path(path)
      while !File.exist?(File.join(path, "prick.yml"))
        path != "/" or raise Error, "Can't find project directory"
        path = File.dirname(path)
      end
      path
    end

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

    def generate_drop_statements
      has_search_path = false
      stmts = []
      for line in lines
        case line
          when /^\s*set\s+search_path/
            sql = line
            has_search_path = true if stmts.empty?
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
        stmts << sql
      end
      [stmts, has_search_path]
    end
  end
end
