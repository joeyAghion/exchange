module Errors
  class ApplicationError < StandardError
    attr_reader :type, :code, :data
    def initialize(type, code, data = nil)
      @type = type
      @code = code
      @data = data
      super(type)
    end
  end
end
