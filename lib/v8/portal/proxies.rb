module V8
  class Portal
    class Proxies

      def initialize
        @js_proxies_rb2js = {}
        @js_proxies_js2rb = {}
        @rb_proxies_rb2js = {}
        @rb_proxies_js2rb = {}
        @clear_js_proxy = ClearJSProxy.new(@js_proxies_rb2js, @js_proxies_js2rb)
        @clear_rb_proxy = ClearRubyProxy.new(@rb_proxies_rb2js, @rb_proxies_js2rb)
      end

      def js2rb(js)
        if rb = js_proxy_2_rb_object(js)
          return rb
        elsif rb = js_object_2_rb_proxy(js)
          return rb
        else
          proxy = block_given? ? yield(js) : Object.new
          register_ruby_proxy proxy, :for => js if proxy && js && js.kind_of?(V8::C::Handle)
          return proxy
        end
      end

      def rb2js(rb)
        if js = rb_proxy_2_js_object(rb)
          return js
        elsif js = rb_object_2_js_proxy(rb)
          return js
        else
          proxy = block_given? ? yield(rb) : V8::C::Object::New()
          register_javascript_proxy proxy, :for => rb unless @js_proxies_rb2js[rb]
          return proxy
        end
      end

      def register_javascript_proxy(proxy, options = {})
        target = options[:for] or fail ArgumentError, "must specify the object that you're proxying with the :for => param"
        fail ArgumentError, "javascript proxy must be a V8::C::Handle, not #{proxy.class}" unless proxy.kind_of?(V8::C::Handle)
        fail DoubleProxyError, "target already has a registered proxy" if @js_proxies_rb2js[target]

        @js_proxies_js2rb[proxy] = target
        @js_proxies_rb2js[target] = proxy
        proxy.MakeWeak(nil, @clear_js_proxy)
        V8::C::V8::AdjustAmountOfExternalAllocatedMemory(16 * 1024)
      end

      def rb_object_2_js_proxy(object)
        @js_proxies_rb2js[object]
      end

      def js_proxy_2_rb_object(proxy)
        @js_proxies_js2rb[proxy]
      end

      def register_ruby_proxy(proxy, options = {})
        target = options[:for] or fail ArgumentError, "must specify the object that you're proxying with the :for => param"
        fail ArgumentError, "'#{proxy.inspect}' is not a Handle to an actual V8 object" unless target.kind_of?(V8::C::Handle)
        @rb_proxies_rb2js[proxy.object_id] = target
        @rb_proxies_js2rb[target] = proxy.object_id
        ObjectSpace.define_finalizer(proxy, @clear_rb_proxy)
        V8::C::V8::AdjustAmountOfExternalAllocatedMemory(8 * 1024)
      end

      def js_object_2_rb_proxy(object)
        if id = @rb_proxies_js2rb[object]
          ObjectSpace._id2ref id
        end
      end

      def rb_proxy_2_js_object(proxy)
        @rb_proxies_rb2js[proxy.object_id]
      end

      def js_empty?
        @js_proxies_rb2js.empty? && @js_proxies_js2rb.empty?
      end

      def rb_empty?
        @rb_proxies_rb2js.empty? && @rb_proxies_js2rb.empty?
      end

      def empty?
        js_empty? && rb_empty?
      end
      DoubleProxyError = Class.new(StandardError)

      class ClearJSProxy

        def initialize(rb2js, js2rb)
          @rb2js, @js2rb = rb2js, js2rb
        end

        def call(proxy, parameter)
          rb = @js2rb[proxy]
          @js2rb.delete(proxy)
          @rb2js.delete(rb)
          V8::C::V8::AdjustAmountOfExternalAllocatedMemory(-16 * 1024)
        end
      end

      class ClearRubyProxy
        def initialize(rb2js, js2rb)
          @rb2js, @js2rb = rb2js, js2rb
        end

        def call(proxy_id)
          js = @rb2js[proxy_id]
          @rb2js.delete(proxy_id)
          @js2rb.delete(js)
          V8::C::V8::AdjustAmountOfExternalAllocatedMemory(-8 * 1024)
        end
      end
    end
  end
end