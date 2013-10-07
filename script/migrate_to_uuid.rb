#!/usr/bin/env ruby

require 'pg'

DBHOST = '127.0.0.1'
DBUSER = 'postgres'
DBNAME = 'cartodb_uuid'

@actions = ['schema', 'rollback', 'meta', 'clean', 'data']

ACTION = ARGV[0]

def usage()
  puts "Usage: #{__FILE__} <action>"
  puts "Actions:"
  @actions.each {|a| puts "  #{a}"}
  exit 1
end

if ACTION.nil? || !@actions.include?(ACTION)
  usage()
end

tables = {
           :api_keys => {
             :related => [],
             :singular => 'api_key'
           },
           :assets => { 
             :related => [],
             :singular => 'asset'
           },
           :client_applications => {
             :related => [],
             :singular => 'client_application'
           },
           :data_imports => {
             :related => [],
             :singular => 'data_import'
           },
           :layers => {
             :related => ['layers_maps', 'layers_users', 'layers_user_tables'],
             :singular => 'layer'
           },
           :layers_maps => {
             :related => [],
             :singular => 'layer_map'
           },
           :layers_user_tables => {
             :related => [],
             :singular => 'layer_user_table'
           },
           :layers_users => {
             :related => [],
             :singular => 'layer_user'
           },
           :maps => {
             :related => ['user_tables', 'layers_maps'],
             :singular => 'map'
           },
           :oauth_nonces => {
             :related => [],
             :singular => 'oauth_nonce'
           },
           :oauth_tokens => {
             :related => [],
             :singular => 'oauth_token'
           },
           :overlays => {
             :related => [],
             :singular => 'overlay'
           },
           :tags => {
             :related => [],
             :singular => 'tag'
           },
           :user_tables => {
             :related => ['data_imports', 'layers_user_tables', 'tags'],
             :singular => 'table'
           },
           :users => {
             :related => ['user_tables', 'maps', 'layers_users', 'assets', 'api_keys', 'client_applications', 'oauth_tokens', 'tags'],
             :singular => 'user'
           },
           :visualizations => {
             :related => ['maps', 'overlays'],
             :singular => 'visualization'
           }
         }


def alter_schema(tables) 
  tables.each do |tname, tinfo|
    # Create main uuid column in every table
    puts "Creating uuid column in #{tname}"
    begin
      @conn.exec("ALTER TABLE #{tname} ADD uuid uuid UNIQUE NOT NULL DEFAULT uuid_generate_v1()")
    rescue => e
      puts "  #{e.error.strip.strip}. Ignoring.."
    end
    tinfo[:related].each do |rtable|
      # Create relation uuid column in a dependent table
      puts "  Creating #{tinfo[:singular]}_uuid column in related table #{rtable}"
      begin
        @conn.exec("ALTER TABLE #{rtable} ADD #{tinfo[:singular]}_uuid uuid")
      rescue => e
        puts "    #{e.error.strip.strip}. Ignoring.."
      end
    end
  end
end

def rollback_schema(tables)
  tables.each do |tname, tinfo|
    tinfo[:related].each do |rtable|
      # Create relation uuid column in a dependent table
      puts "Dropping #{tinfo[:singular]}_uuid column in related table #{rtable}"
      begin
        @conn.exec("ALTER TABLE #{rtable} DROP IF EXISTS #{tinfo[:singular]}_uuid")
      rescue => e
        puts "  #{e.error.strip.strip}. Ignoring.."
      end
    end
    # Destroy main uuid column in every table
    puts "Dropping uuid column in #{tname}"
    begin
      @conn.exec("ALTER TABLE #{tname} DROP IF EXISTS uuid")
    rescue => e
      puts "  #{e.error.strip.strip}. Ignoring.."
    end
  end
end

def migrate_meta(tables)
  tables.each do |tname, tinfo|
    @conn.exec("SELECT id,uuid FROM #{tname}") do |result|
      result.each do |row|
        tinfo[:related].each do |rtable|
          @conn.exec("UPDATE #{rtable} SET #{tinfo[:singular]}_uuid=#{row['uuid']} WHERE #{tinfo[:singular]}_id=#{row['id']}")        
        end
      end
    end
  end
end

def migrate_data()
end

def clean_db(tables)
  tables.each do |tname, tinfo|
    # Drop old id relation column in every table
    puts "Dropping #{tinfo[:singular]}_id from #{tname}"
    begin
      @conn.exec("ALTER TABLE #{tname} DROP IF EXISTS #{tinfo[:singular]}_id")
    rescue => e
      puts "  #{e.error.strip.strip}. Ignoring.."
    end
    # Rename new uuid relation column to id
    puts "Renaming #{tinfo[:singular]}_uuid to #{tinfo[:singular]}_id"
    begin
      @conn.exec("ALTER TABLE #{tname} RENAME #{tinfo[:singular]}_uuid TO #{tinfo[:singular]}_id")
    rescue => e
      puts "  #{e.error.strip.strip}. Ignoring.."
    end
  end
end

@conn = PGconn.connect( host: DBHOST, user: DBUSER, dbname: DBNAME )

if ACTION == 'schema'
  alter_schema(tables)
elsif ACTION == 'rollback'
  rollback_schema(tables)
elsif ACTION == 'meta'
  migrate_meta(tables)
elsif ACTION == 'data'
  migrate_data()
elsif ACTION == 'clean'
  clean_db(tables)
end
