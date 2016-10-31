require "open3"
require "multi_json"

module Ecsr
  module Runner
    class Docker
      attr_reader \
        :name,
        :container_definition,
        :rm,
        :use_sudo

      def initialize(options)
        @name = options[:name]
        @container_definition = options[:container_definition]
        @rm = options[:rm]
        @use_sudo = options[:use_sudo]
      end

      def run(class_name, method_name, args, container_definition_overrides: {}, environments: [])
        definition = container_definition
          .merge(container_definition_overrides)

        cmd = use_sudo ? "sudo docker" : "docker"
        cmdopt = ["run"]
        cmdopt.concat(["--rm"]) if rm
        cmdopt.concat(base_environments(class_name, method_name, args))
        cmdopt.concat(["--cpu-shares", definition[:cpu].to_s]) if definition[:cpu]
        cmdopt.concat(["--memory", "#{definition[:memory]}m"]) if definition[:memory]
        cmdopt.concat(["--memory-reservation", "#{definition[:memory_reservation]}m"]) if definition[:memory_reservation]
        cmdopt.concat(extract_environments(environments))
        cmdopt.concat([definition[:image], "bundle", "exec", "rake", "ecsr:run"])

        Open3.popen3(cmd, *cmdopt) do |stdin, stdout, stderr, wait_thr|
          stdin.close_write
          begin
            loop do
              rs, _ = IO.select([stdout, stderr])
              rs.each do |io|
                io.each do |line|
                  next if line.nil? || line.empty?
                  if io == stdout
                    $stdout.puts(line)
                  else
                    $stderr.puts(line)
                  end
                end
              end
              break if stdout.eof? && stderr.eof?
            end
          rescue EOFError
          end
        end
      end

      private

      def base_environments(class_name, method_name, args)
        ["-e", "#{CLASS_NAME_ENV}=#{class_name}", "-e", "#{METHOD_NAME_ENV}=#{method_name}", "-e", "#{METHOD_ARGS_ENV}=#{MultiJson.dump(args)}"]
      end

      def extract_environments(environments)
        environments.flat_map do |e|
          ["-e", "#{e[:name]}=#{e[:value]}"]
        end
      end
    end
  end
end