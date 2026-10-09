# Executes only local builtins: no SSH, compose, Kubernetes API, or guest mutation.
require 'tmpdir'
require 'fileutils'
require 'yaml'
require 'json'
require 'open3'

root = File.expand_path('..', __dir__)
Dir.mktmpdir('plan0007-byo-inventory-') do |dir|
  result = File.join(dir, 'host-result')
  play = [{'hosts' => 'localhost', 'gather_facts' => false,
           'roles' => ['openshift-image-builder-imi'],
           'tasks' => [{'ansible.builtin.assert' => {'that' => [
             "hostvars['pipeline_target_host'].ansible_ssh_host == image_builder_host",
             "hostvars['pipeline_target_host'].ansible_ssh_port == '22'",
             "lookup('file', image_builder_host_output_file) == image_builder_host"
           ]}}]}]
  playbook = File.join(dir, 'test.yaml')
  File.write(playbook, YAML.dump(play))
  env = {'ANSIBLE_LOCAL_TEMP' => File.join(dir, 'local'), 'ANSIBLE_REMOTE_TEMP' => File.join(dir, 'remote'),
         'ANSIBLE_ROLES_PATH' => File.join(root, 'ansible', 'roles')}
  ['builder.example.com', '192.0.2.10', 'bad;command', "builder.example.com\n"].each_with_index do |host, index|
    File.unlink(result) if File.exist?(result)
    vars = {'image_builder_host' => host, 'image_builder_host_output_file' => result}
    out, err, status = Open3.capture3(env, 'ansible-playbook', '-i', 'localhost,', '-c', 'local', '-e', JSON.dump(vars), playbook)
    raise "Unexpected inventory result for #{host.inspect}: #{out}\n#{err}" unless status.success? == (index < 2)
    raise 'Invalid host produced a result' if index >= 2 && File.exist?(result)
    raise 'Managed VMI tasks were included' if out.include?('Query VirtualMachineInstances')
  end
end
# Both compose playbooks must skip the scheduler (which re-queries VMI) with an explicit host.
%w[oci-create-image oci-build-installer-image].each do |name|
  playbook = YAML.load_file(File.join(root, 'ansible', 'playbooks', "#{name}.yaml"))
  role = playbook.flat_map { |play| play['roles'] || [] }.find { |r| r['role'] == 'pipeline-scheduler' }
  raise 'Explicit host still schedules through VMI' unless role['when'] == "image_builder_host | default('') | length == 0"
end
puts '4 local Ansible inventory cases and both scheduler guards passed'

# Execute real HTTPD add_host tasks with a local pod-query fixture. Only the API
# authentication arguments are replaced; namespace/selector and task flow remain.
Dir.mktmpdir('plan0007-httpd-inventory-') do |dir|
  collection = File.join(dir, 'collections', 'ansible_collections', 'community', 'kubernetes', 'plugins', 'modules')
  FileUtils.mkdir_p(collection)
  File.write(File.join(collection, 'k8s_info.py'), <<~PY)
    from ansible.module_utils.basic import AnsibleModule
    def main():
        module = AnsibleModule(argument_spec=dict(
            api_key=dict(type='str', no_log=True), api_version=dict(type='str'),
            ca_cert=dict(type='str'), host=dict(type='str'), kind=dict(type='str'),
            label_selectors=dict(type='list', elements='str'), namespace=dict(type='str'),
            validate_certs=dict(type='bool')))
        if module.params['namespace'] != 'serving-pods' or module.params['label_selectors'] != ['app=existing-httpd']:
            module.fail_json(msg='HTTPD pod query lost configured namespace or selector')
        module.exit_json(changed=False, resources=[dict(metadata=dict(name='existing-httpd-pod'))])
    if __name__ == '__main__':
        main()
  PY
  tasks = YAML.load_file(File.join(root, 'ansible', 'roles', 'openshift-httpd-pod-imi', 'tasks', 'main.yaml'))
  tasks.first['community.kubernetes.k8s_info']['api_key'] = 'local-fixture'
  tasks.first['community.kubernetes.k8s_info']['ca_cert'] = '/fixture/ca.crt'
  upload = YAML.load_file(File.join(root, 'ansible', 'roles', 'content-download-upload', 'tasks', 'upload-rfe-artifact.yaml'))
  upload_add_host = upload.flat_map { |t| t['block'] || [] }.find { |t| t['name'] == 'Add HTTPD Pod as Host' }
  raise 'HTTPD upload inventory task missing' unless upload_add_host
  tasks += [{'ansible.builtin.set_fact' => {'httpd_pod' => 'upload-httpd-pod'}}, upload_add_host]
  iso = YAML.load_file(File.join(root, 'ansible', 'roles', 'oci-build-auto-iso', 'tasks', 'main.yaml'))
  destination = iso.find { |t| t['name'] == 'Pull ISO From Image Builder to httpd Pod' }.dig('ansible.builtin.get_url', 'dest')
  tasks << {'ansible.builtin.assert' => {'that' => [
    "hostvars['existing-httpd-pod'].ansible_kubectl_namespace == 'serving-pods'",
    "hostvars['upload-httpd-pod'].ansible_kubectl_namespace == 'serving-pods'",
    "'existing-httpd-pod' in groups.httpd_pod_group",
    "iso_httpd_destination == '/srv/edge/generated.iso'",
    "edge_iso_path == '/var/www/html/generated.iso'"
  ]}}
  playbook = File.join(dir, 'httpd.yaml')
  File.write(playbook, YAML.dump([{'hosts' => 'localhost', 'gather_facts' => false,
    'vars' => {'httpd_pod_namespace' => 'serving-pods', 'httpd_pod_label_selector' => 'app=existing-httpd',
               'httpd_web_root' => '/srv/edge', 'edge_iso_path' => '/var/www/html/generated.iso', 'iso_httpd_destination' => destination},
    'tasks' => tasks}]))
  env = {'ANSIBLE_LOCAL_TEMP' => File.join(dir, 'local'), 'ANSIBLE_REMOTE_TEMP' => File.join(dir, 'remote'),
         'ANSIBLE_COLLECTIONS_PATH' => File.join(dir, 'collections')}
  out, err, status = Open3.capture3(env, 'ansible-playbook', '-i', 'localhost,', '-c', 'local', playbook)
  raise "HTTPD inventory fixture failed: #{out}\n#{err}" unless status.success?
end
puts 'HTTPD pod-query fixture, both actual add_host namespace paths and ISO destination passed'
