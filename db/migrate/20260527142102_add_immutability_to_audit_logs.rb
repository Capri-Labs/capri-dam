class AddImmutabilityToAuditLogs < ActiveRecord::Migration[7.0]
  def up
    execute <<-SQL
      CREATE OR REPLACE FUNCTION protect_audit_logs() RETURNS TRIGGER AS $$
      BEGIN
        RAISE EXCEPTION 'Audit logs are immutable and cannot be updated or deleted.';
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER trigger_protect_audit_logs
      BEFORE UPDATE OR DELETE ON audit_logs
      FOR EACH ROW EXECUTE PROCEDURE protect_audit_logs();
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS trigger_protect_audit_logs ON audit_logs;"
    execute "DROP FUNCTION IF EXISTS protect_audit_logs();"
  end
end