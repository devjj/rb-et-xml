# Convenience Module providing Net:HTTP for SSL.
# http://almaer.com/blog/gspreadsheet-running-formulas-from-the-command-line
module Net
  class HTTPS < HTTP
    def initialize(address, port = nil)
      super(address, port)    
      self.use_ssl = true
    end
  end
end
