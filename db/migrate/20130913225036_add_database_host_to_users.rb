Sequel.migration do
  change do
    alter_table :users do
      add_column :database_host, String
    end
  end
end
