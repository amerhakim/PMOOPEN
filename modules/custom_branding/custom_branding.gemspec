Gem::Specification.new do |s|
  s.name        = "custom_branding"
  s.version     = "1.0.0"
  s.authors     = ["OpenProject GmbH"]
  s.summary     = "Custom logo and interface colors, independent of the Enterprise edition."

  s.files = Dir["{app,config,db,lib}/**/*"]
  s.metadata["rubygems_mfa_required"] = "true"
end
