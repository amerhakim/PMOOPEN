Gem::Specification.new do |s|
  s.name        = "impersonation"
  s.version     = "1.0.0"
  s.authors     = ["OpenProject GmbH"]
  s.summary     = "Admin-only 'log in as' tool for QA/testing role-specific behaviour."

  s.files = Dir["{app,config,db,lib}/**/*"]
  s.metadata["rubygems_mfa_required"] = "true"
end
