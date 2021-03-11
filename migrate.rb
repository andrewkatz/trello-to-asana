# frozen_string_literal: true

require 'asana'
require 'awesome_print'
require 'tacokit'
require 'tty-prompt'

TRELLO_MAX = 1_000_000

trello_client = Tacokit::Client.new(
  app_key: ENV['TRELLO_APP_KEY'],
  app_token: ENV['TRELLO_APP_TOKEN']
)
asana_client = Asana::Client.new do |c|
  c.authentication :access_token, ENV['ASANA_TOKEN']
  c.default_headers 'asana-enable' => 'new_user_task_lists'
end
prompt = TTY::Prompt.new

puts 'Fetching Trello boards'
boards = trello_client.boards

choices = boards.map do |board|
  { name: board.name, value: board.id }
end
board_id = prompt.enum_select('Which Trello board do you want to migrate?', choices)

board = trello_client.board(board_id)

puts "\nFetching Asana workspaces"
workspaces = asana_client.workspaces.find_all
raise 'Expected only 1 workspace' unless workspaces.size == 1

workspace = workspaces.first
puts "Found workspace: #{workspace.name}"

puts "\nCreating Asana project"
project = asana_client.projects.create_in_workspace(
  workspace: workspace.gid,
  name: "#{board.name} (Migrated from Trello)"
)
puts "Created Asana project: #{project.name}"

puts "\nFetching Trello lists for #{board.name}"
lists = trello_client.lists(board)

lists.each do |list|
  puts "\nMigrating list #{list.name}"

  puts 'Creating section'
  section = asana_client.sections.create_in_project(project: project.gid, name: list.name)

  puts 'Fetching cards'
  cards = trello_client.list_cards(list, max: TRELLO_MAX)

  puts 'Creating tasks'
  processed_cards = []
  cards.each do |card|
    next if processed_cards.include?(card.id)

    puts "Creating task #{card.id} - #{card.name}"
    task = asana_client.tasks.create_in_workspace(
      workspace: workspace.gid,
      name: card.name,
      notes: [card.desc, "Trello URL: #{card.url}"].join("\n\n"),
      due_at: card.due ? card.due.strftime('%Y-%m-%dT%H:%M:%S.%L%z') : nil,
      completed: card.closed
    )
    puts 'Adding to project / section'
    task.add_project(project: project.gid, section: section.gid)

    multiple_checklists = card.checklist_ids.size > 1

    card.checklist_ids.each do |checklist_id|
      puts "Fetching checklist #{checklist_id}"
      checklist = trello_client.checklist(checklist_id)

      puts "Fetching items on checklist #{checklist.name}"
      check_items = []
      processed_check_items = []

      trello_client.check_items(checklist).each do |check_item|
        check_items << check_item
      end

      check_items.sort { |a, b| b.pos <=> a.pos }.each do |check_item|
        next if processed_check_items.include?(check_item.id)

        puts "Creating subtask #{check_item.name}"
        task.add_subtask(
          name: [(checklist.name if multiple_checklists), check_item.name].compact.join(': '),
          completed: check_item.state == 'complete'
        )

        processed_check_items << check_item.id
      end
    end

    puts 'Fetching comments'
    comments = trello_client.card_actions(card, filter: 'comment_card')
    comments.each do |comment|
      text = "#{comment[:member_creator][:full_name]}:\n#{comment[:data][:text]}"
      puts "Adding comment: '#{text}'"
      task.add_comment(text: text)
    end

    processed_cards << card.id
  end
end
