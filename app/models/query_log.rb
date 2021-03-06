# Tracks execution for a query sent by a client
class QueryLog < ActiveRecord::Base
  def self.start(params = {})
    query_log = new(params.to_h.merge(started_at: Time.now))
    query_log.save
    query_log
  end

  def complete(result)
    update(result: result, completed_at: Time.now)
  end

  def fail(error)
    update(completed_at: Time.now, error: error)
  end

  def ctdl=(value)
    super(value.present? ? value.to_json : nil)
  end

  def result=(value)
    super(value.present? ? value.to_json : nil)
  end

  def query_logic=(value)
    super(value.present? ? value.to_json : nil)
  end
end
