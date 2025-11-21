# For simple boolean flags
class EnvHelper
  def self.enabled?(key)
    ['true', '1', 'yes', 'on'].include?(ENV[key].to_s.downcase)
  end

  def self.set?(key)
    !ENV[key].to_s.empty?
  end
end
