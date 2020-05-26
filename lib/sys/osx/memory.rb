require 'ffi'

module Sys
  module Memory
    extend FFI::Library
    ffi_lib FFI::Library::LIBC

    HOST_VM_INFO64 = 4
    HOST_VM_INFO64_COUNT = 38

    attach_function :sysctlbyname, [:string, :pointer, :pointer, :pointer, :size_t], :int
    attach_function :host_page_size, [:pointer, :pointer], :int
    attach_function :host_statistics64, [:pointer, :int, :pointer, :pointer], :int
    attach_function :mach_host_self, [], :pointer

    typedef :uint, :natural_t

    class Swap < FFI::Struct
      layout(
        :xsu_total, :uint64_t,
        :xsu_avail, :uint64_t,
        :xsu_used, :uint64_t,
        :xsu_pagesize, :uint32_t,
        :xsu_encrypted, :bool
      )
    end

    class VmStat < FFI::Struct
      layout(
        :free_count, :natural_t,             # of pages free
        :active_count, :natural_t,           # of pages active
        :inactive_count, :natural_t,         # of pages inactive
        :wire_count, :natural_t,             # of pages wired down
        :zero_fill_count, :uint64_t,         # of zero fill pages
        :reactivations, :uint64_t,           # of pages reactivated
        :pageins, :uint64_t,                 # of pageins
        :pageouts, :uint64_t,                # of pageouts
        :faults, :uint64_t,                  # of faults
        :cow_faults, :uint64_t,              # of copy-on-writes
        :lookups, :uint64_t,                 # object cache lookups
        :hits, :uint64_t,                    # object cache hits
        :purges, :uint64_t,                  # of pages purged
        :purgeable_count, :natural_t,        # of pages purgeable
        :speculative_count, :natural_t,      # of pages speculative
        :decompressions, :uint64_t,          # of pages decompressed
        :compressions, :uint64_t,            # of pages compressed
        :swapins, :uint64_t,                 # of pages swapped in (via compression segments)
        :swapouts, :uint64_t,                # of pages swapped out (via compression segments)
        :compressor_page_count, :natural_t,  # of pages used by the compressed pager to hold all the compressed data
        :throttled_count, :natural_t,        # of pages throttled
        :external_page_count, :natural_t,    # of pages that are file-backed (non-swap)
        :internal_page_count, :natural_t,    # of pages that are anonymous
        :total_uncompressed_pages_in_compressor, :uint64_t # of pages (uncompressed) held within the compressor
      )
    end

    def memory
      hash = {}
      page_size = 4096 # Possibly changed later

      begin
        optr = FFI::MemoryPointer.new(:uint64_t)
        size = FFI::MemoryPointer.new(:size_t)
        size.write_int(optr.size)

        if sysctlbyname('hw.memsize', optr, size, nil, 0) < 0
          raise Error, "sysctlbyname function failed"
        end

        hash[:total] = optr.read_uint64
      ensure
        optr.free if optr && !optr.null?
        size.clear
      end

      begin
        swap = Swap.new
        size.write_int(swap.size)

        if sysctlbyname('vm.swapusage', swap, size, nil, 0) < 0
          raise Error, "sysctlbyname function failed"
        end

        hash[:swap_total] = swap[:xsu_total]
        hash[:swap_available] = swap[:xsu_avail]
        hash[:swap_used] = swap[:xsu_used]
        page_size = swap[:xsu_pagesize]
      ensure
        size.free if size && !size.null?
      end

      host_self = mach_host_self()
      vmstat = VmStat.new
      count = FFI::MemoryPointer.new(:size_t)
      count.write_int(vmstat.size)

      rv = host_statistics64(host_self, HOST_VM_INFO64, vmstat, count)
      raise SystemCallError.new('host_statistics64', rv) if rv != 0

      hash[:free] = vmstat[:free_count] * page_size
      hash[:active] = vmstat[:active_count] * page_size
      hash[:inactive] = vmstat[:inactive_count] * page_size
      hash[:speculative] = vmstat[:speculative_count] * page_size
      hash[:wire] = vmstat[:wire_count] * page_size
      hash[:compressed] = vmstat[:compressor_page_count] * page_size

      hash
    ensure
      count.free if count && !count.null?
    end

    # Total physical memory in bytes.
    #
    def total
      memory[:total]
    end

    # The physical memory currently available, in bytes.
    #
    def free
      memory[:free]
    end

    # The physical memory, in bytes, currently in use.
    def used
      total - free
    end

    # A number between 0 and 100 that specifies the approximate percentage of
    # physical memory that is in use.
    #
    def load
      (used / total.to_f).round(2) * 100
    end

    module_function :memory, :total, :free, :load, :used
  end
end