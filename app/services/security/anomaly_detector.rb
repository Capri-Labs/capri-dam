module Security
  class AnomalyDetector
    def self.analyze(user_id)
      logs = AuditLog.where(user_id: user_id, created_at: 1.hour.ago..)

      # AI Logic: Detect rapid-fire admin changes or unauthorized access
      if logs.where(action: 'update', auditable_type: 'User').count > 10
        trigger_security_alert(user_id, "Rapid Admin modifications detected.")
      end
    end
  end
end