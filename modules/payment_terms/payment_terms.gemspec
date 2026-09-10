Gem::Specification.new do |s|
  s.name        = "payment_terms"
  s.version     = "1.0.0"
  s.authors     = ["OpenProject GmbH"]
  s.summary     = "Client payment schedule tracking per project (contract lines, installments, invoicing), restricted to PM and above."

  s.files = Dir["{app,config,db,lib}/**/*"]
  s.metadata["rubygems_mfa_required"] = "true"
end
