action :create do
  user_connection = {
    :host => new_resource.host,
    :username => new_resource.username,
    :password => new_resource.password
  }
  root_connection = {
    :host => new_resource.host,
    :username => new_resource.root_username,
    :password => new_resource.root_password
  }

  zabbix_tmp_path = "/tmp/zabbix-#{new_resource.zabbix_server_version}"
  zabbix_tar_path =  "#{new_resource.zabbix_source_dir}/zabbix-#{new_resource.zabbix_server_version}-database.tar.gz"
  zabbix_path = ::File.join(new_resource.zabbix_source_dir, "zabbix-#{new_resource.zabbix_server_version}-database")
  # get the zabbix files
  script "extract_zabbix_database" do
    interpreter "bash"
    user "root"
    cwd new_resource.zabbix_source_dir
    action :nothing
    code <<-EOH
      rm -rf #{zabbix_tmp_path}
      tar xvfz #{zabbix_tar_path} -C /tmp
      mv #{zabbix_tmp_path} #{zabbix_path}
    EOH
  end

  # Download zabbix source code
  remote_file zabbix_tar_path do
    source "http://downloads.sourceforge.net/project/zabbix/#{node['zabbix']['server']['branch']}/#{node['zabbix']['server']['version']}/zabbix-#{node['zabbix']['server']['version']}.tar.gz"
    mode "0644"
    action :create_if_missing
    notifies :run, "script[extract_zabbix_database]", :immediately
  end

  # create zabbix database
  mysql_database new_resource.dbname do
    connection root_connection
    action :create
    notifies :run, "execute[zabbix_populate_schema]", :immediately
    notifies :run, "execute[zabbix_populate_image]", :immediately
    notifies :run, "execute[zabbix_populate_data]", :immediately
    notifies :create, "mysql_database_user[#{new_resource.username}]", :immediately
    notifies :grant, "mysql_database_user[#{new_resource.username}]", :immediately
  end

  # populate database
  executable = "/usr/bin/mysql"
  root_username = "-u #{new_resource.root_username}"
  root_password = "-p#{new_resource.root_password}"
  host = "-h #{new_resource.host}"
  dbname = "#{new_resource.dbname}"
  sql_command = "#{executable} #{root_username} #{root_password} #{host} #{dbname}"

  sql_scripts = if new_resource.zabbix_server_version.to_f < 2.0
                  Chef::Log.info "Version 1.x branch of zabbix in use"
                  [
                    ["zabbix_populate_schema", ::File.join(zabbix_path, "create", "schema", "mysql.sql")],
                    ["zabbix_populate_data", ::File.join(zabbix_path, "create", "data", "data.sql")],
                    ["zabbix_populate_image", ::File.join(zabbix_path, "create", "data", "images_mysql.sql")],
                  ]
                else
                  Chef::Log.info "Version 2.x branch of zabbix in use"
                  [
                    ["zabbix_populate_schema", ::File.join(zabbix_path, "database", "mysql", "schema.sql")],
                    ["zabbix_populate_data", ::File.join(zabbix_path, "database", "mysql", "data.sql")],
                    ["zabbix_populate_image", ::File.join(zabbix_path, "database", "mysql", "images.sql")],
                  ]
                end

  sql_scripts.each do |script_spec|
    script_name = script_spec.first
    script_path = script_spec.last

    execute script_name do
      command "#{sql_command} < #{script_path}"
      action :nothing
    end
  end

  # create and grant zabbix user
  mysql_database_user new_resource.username do
    connection root_connection
    password new_resource.password
    database_name new_resource.dbname
    host new_resource.allowed_user_hosts
    privileges [:select,:update,:insert,:create,:drop,:delete]
    action :nothing
  end

end
