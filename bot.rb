require 'telegram/bot'
require 'json'

TOKEN = 'ключ'
QUOTES_FILE = 'quotes.json'
USER_STATE = {}
ACTIVE_USERS = {}
TEMP_QUOTES = {}

def load_quotes
  File.exist?(QUOTES_FILE) ? JSON.parse(File.read(QUOTES_FILE)) : []
end

def save_quotes(quotes)
  File.write(QUOTES_FILE, JSON.pretty_generate(quotes))
end

def random_quote
  quotes = load_quotes
  quotes.empty? ? "Цитат поки немає" : quotes.sample
end

# ---- Перевірка сміттєвого тексту з блокуванням спецсимволів ----
def looks_like_gibberish?(text)
  text = text.strip
  return true if text.empty?

  forbidden_chars = %w[@ # $ % ^ & * ( ) _ + = { } [ ] | \\ / < > ~ `]

  return true if forbidden_chars.any? { |c| text.include?(c) }
  return true if text.match?(/^\d+$/)

  letters_count = text.scan(/[a-zA-ZА-Яа-яЇїІіЄє]/).size
  return true if letters_count < 3

  unique_ratio = text.chars.uniq.length.to_f / text.length
  return true if unique_ratio < 0.5 && text.length >= 4

  false
end

# ---- Перевірка на дублікати (ігноруємо автора) ----

def add_quote(full_text)
  quotes = load_quotes
  quotes << full_text
  save_quotes(quotes)
end

def send_command_menu(bot, chat_id)
  bot.api.send_message(
    chat_id: chat_id,
    text: "❓ Команди:\n/quote — випадкова цитата\n/addquote — додати цитату\n/stop — вийти"
  )
end

def prompt_quote_input(bot, chat_id)
  bot.api.send_message(
    chat_id: chat_id,
    text: "📝 Введіть цитату, яку хочете додати:\n*Приклад:*\n_Кожен день — це нова можливість змінити своє життя_",
    parse_mode: "Markdown"
  )
end

# ---- Запуск бота ----
Telegram::Bot::Client.run(TOKEN) do |bot|
  puts "Бот запущено..."

  bot.api.set_my_commands(
    commands: [
      {command: 'start', description: 'Запустити бота'},
      {command: 'quote', description: 'Отримати випадкову цитату'},
      {command: 'addquote', description: 'Додати нову цитату'},
      {command: 'stop', description: 'Припинити розмову'}
    ]
  )

  bot.listen do |message|
    chat_id = message.chat.id
    text = message.text.to_s.strip

    # ---- Стан: очікуємо цитату ----
    if USER_STATE[chat_id] == :adding_quote_text
      if looks_like_gibberish?(text)
        bot.api.send_message(chat_id: chat_id, text: "❗ Неправильна цитата. Спробуйте ще раз.")
        prompt_quote_input(bot, chat_id)
        next
      end

      if text.length < 5
        bot.api.send_message(chat_id: chat_id, text: "❗ Цитата занадто коротка. Спробуйте ще раз.")
        prompt_quote_input(bot, chat_id)
        next
      end

      if text.length > 300
        bot.api.send_message(chat_id: chat_id, text: "❗ Цитата занадто довга. Спробуйте ще раз.")
        prompt_quote_input(bot, chat_id)
        next
      end

      TEMP_QUOTES[chat_id] = text
      USER_STATE[chat_id] = :adding_quote_author
      bot.api.send_message(chat_id: chat_id, text: "📝 Тепер введіть автора цитати. Якщо не знаєте автора, напишіть 'невідомий автор'.")
      next
    end

    # ---- Стан: очікуємо автора ----
    if USER_STATE[chat_id] == :adding_quote_author
      author = text.strip
      if looks_like_gibberish?(author)
        bot.api.send_message(chat_id: chat_id, text: "❗ Неправильний автор. Спробуйте ще раз.")
        bot.api.send_message(chat_id: chat_id, text: "📝 Введіть автора цитати або 'невідомий автор'")
        next
      end

      author = "Невідомий автор" if author.empty?
      full_quote = "#{TEMP_QUOTES[chat_id]} — #{author}"
      add_quote(full_quote)
      USER_STATE.delete(chat_id)
      TEMP_QUOTES.delete(chat_id)
      ACTIVE_USERS[chat_id] = true

      bot.api.send_message(chat_id: chat_id, text: "✨ Цитату додано!\n#{full_quote}")
      next
    end

    # ---- Обробка команд ----
    case text
    when '/start'
      ACTIVE_USERS[chat_id] = true
      bot.api.send_message(chat_id: chat_id,
        text: "Привіт, #{message.from.first_name}! 👋\nЯ — бот цитат.\n" \
              "/quote — випадкова цитата\n/addquote — додати цитату\n/stop — припинити розмову"
      )

    when '/stop'
      ACTIVE_USERS.delete(chat_id)
      USER_STATE.delete(chat_id)
      TEMP_QUOTES.delete(chat_id)
      bot.api.send_message(chat_id: chat_id, text: "😴 Ви припинили розмову. Надішліть /start, щоб повернутися.")

    when '/quote'
      if ACTIVE_USERS[chat_id]
        bot.api.send_message(chat_id: chat_id, text: "💬 #{random_quote}")
      else
        bot.api.send_message(chat_id: chat_id, text: "❌ Надішліть /start, щоб продовжити.")
      end

    when '/addquote'
      if ACTIVE_USERS[chat_id]
        USER_STATE[chat_id] = :adding_quote_text
        prompt_quote_input(bot, chat_id)
      else
        bot.api.send_message(chat_id: chat_id, text: "❌ Надішліть /start, щоб продовжити.")
      end

    else
      if ACTIVE_USERS[chat_id]
        send_command_menu(bot, chat_id)
      else
        bot.api.send_message(chat_id: chat_id, text: "❌ Надішліть /start, щоб продовжити.")
      end
    end
  end
end
