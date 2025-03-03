import DesignSystem
import EmojiText
import Env
import Models
import Network
import Shimmer
import SwiftUI

public struct StatusRowView: View {
  @Environment(\.redactionReasons) private var reasons
  @EnvironmentObject private var preferences: UserPreferences
  @EnvironmentObject private var account: CurrentAccount
  @EnvironmentObject private var theme: Theme
  @EnvironmentObject private var client: Client
  @EnvironmentObject private var routerPath: RouterPath
  @StateObject var viewModel: StatusRowViewModel

  public init(viewModel: StatusRowViewModel) {
    _viewModel = StateObject(wrappedValue: viewModel)
  }

  public var body: some View {
    if viewModel.isFiltered, let filter = viewModel.filter {
      switch filter.filter.filterAction {
      case .warn:
        makeFilterView(filter: filter.filter)
      case .hide:
        EmptyView()
      }
    } else {
      HStack(alignment: .top, spacing: .statusColumnsSpacing) {
        if !viewModel.isCompact,
           theme.avatarPosition == .leading,
           let status: AnyStatus = viewModel.status.reblog ?? viewModel.status
        {
          Button {
            routerPath.navigate(to: .accountDetailWithAccount(account: status.account))
          } label: {
            AvatarView(url: status.account.avatar, size: .status)
          }
        }
        VStack(alignment: .leading) {
          if !viewModel.isCompact {
            reblogView
            replyView
          }
          statusView
          if viewModel.showActions && !viewModel.isRemote, theme.statusActionsDisplay != .none {
            StatusActionsView(viewModel: viewModel)
              .padding(.top, 8)
              .tint(viewModel.isFocused ? theme.tintColor : .gray)
              .contentShape(Rectangle())
              .onTapGesture {
                viewModel.navigateToDetail(routerPath: routerPath)
              }
          }
        }
      }
      .onAppear {
        if reasons.isEmpty {
          viewModel.client = client
          if !viewModel.isCompact, viewModel.embeddedStatus == nil {
            Task {
              await viewModel.loadEmbeddedStatus()
            }
          }
          if preferences.serverPreferences?.autoExpandSpoilers == true {
            viewModel.displaySpoiler = false
          }
        }
      }
      .contextMenu {
        StatusRowContextMenu(viewModel: viewModel)
      }
      .accessibilityElement(children: viewModel.isFocused ? .contain : .combine)
      .accessibilityActions {
        // Add the individual mentions as accessibility actions
        ForEach(viewModel.status.mentions, id: \.id) { mention in
          Button("@\(mention.username)") {
            routerPath.navigate(to: .accountDetail(id: mention.id))
          }
        }

        Button(viewModel.displaySpoiler ? "status.show-more" : "status.show-less") {
          withAnimation {
            viewModel.displaySpoiler.toggle()
          }
        }

        Button("@\(viewModel.status.account.username)") {
          routerPath.navigate(to: .accountDetail(id: viewModel.status.account.id))
        }

        StatusRowContextMenu(viewModel: viewModel)
      }
      .background {
        Color.clear
          .contentShape(Rectangle())
          .onTapGesture {
            viewModel.navigateToDetail(routerPath: routerPath)
          }
      }
    }
  }

  private func makeFilterView(filter: Filter) -> some View {
    HStack {
      Text("status.filter.filtered-by-\(filter.title)")
      Button {
        withAnimation {
          viewModel.isFiltered = false
        }
      } label: {
        Text("status.filter.show-anyway")
      }
    }
  }

  @ViewBuilder
  private var reblogView: some View {
    if viewModel.status.reblog != nil {
      HStack(spacing: 2) {
        Image(systemName: "arrow.left.arrow.right.circle.fill")
        AvatarView(url: viewModel.status.account.avatar, size: .boost)
        if viewModel.status.account.username != account.account?.username {
          EmojiTextApp(.init(stringValue: viewModel.status.account.safeDisplayName), emojis: viewModel.status.account.emojis)
          Text("status.row.was-boosted")
        } else {
          Text("status.row.you-boosted")
        }
      }
      .accessibilityElement()
      .accessibilityLabel(
        Text("\(viewModel.status.account.safeDisplayName)")
          + Text(" ")
          + Text(viewModel.status.account.username != account.account?.username ? "status.row.was-boosted" : "status.row.you-boosted")
      )
      .font(.scaledFootnote)
      .foregroundColor(.gray)
      .fontWeight(.semibold)
      .onTapGesture {
        if viewModel.isRemote, let url = viewModel.status.account.url {
          Task {
            await routerPath.navigateToAccountFrom(url: url)
          }
        } else {
          routerPath.navigate(to: .accountDetailWithAccount(account: viewModel.status.account))
        }
      }
    }
  }

  @ViewBuilder
  var replyView: some View {
    if let accountId = viewModel.status.inReplyToAccountId,
       let mention = viewModel.status.mentions.first(where: { $0.id == accountId })
    {
      HStack(spacing: 2) {
        Image(systemName: "arrowshape.turn.up.left.fill")
        Text("status.row.was-reply")
        Text(mention.username)
      }
      .font(.scaledFootnote)
      .foregroundColor(.gray)
      .fontWeight(.semibold)
      .onTapGesture {
        if viewModel.isRemote {
          Task {
            await routerPath.navigateToAccountFrom(url: mention.url)
          }
        } else {
          routerPath.navigate(to: .accountDetail(id: mention.id))
        }
      }
    }
  }

  private var statusView: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let status: AnyStatus = viewModel.status.reblog ?? viewModel.status {
        if !viewModel.isCompact {
          HStack(alignment: .top) {
            Button {
              if viewModel.isRemote, let url = status.account.url {
                Task {
                  await routerPath.navigateToAccountFrom(url: url)
                }
              } else {
                routerPath.navigate(to: .accountDetailWithAccount(account: status.account))
              }
            } label: {
              accountView(status: status)
            }
            .buttonStyle(.plain)
            Spacer()
            menuButton
              .accessibilityHidden(true)
          }
          .accessibilityElement()
          .accessibilityLabel(Text("\(status.account.displayName), \(status.createdAt.formatted)"))
        }
        makeStatusContentView(status: status)
          .contentShape(Rectangle())
          .onTapGesture {
            viewModel.navigateToDetail(routerPath: routerPath)
          }
      }
    }
    .accessibilityElement(children: viewModel.isFocused ? .contain : .combine)
    .accessibilityAction {
      viewModel.navigateToDetail(routerPath: routerPath)
    }
  }

  private func makeStatusContentView(status: AnyStatus) -> some View {
    Group {
      if !status.spoilerText.asRawText.isEmpty {
        EmojiTextApp(status.spoilerText, emojis: status.emojis, language: status.language)
          .font(.scaledBody)
        Button {
          withAnimation {
            viewModel.displaySpoiler.toggle()
          }
        } label: {
          Text(viewModel.displaySpoiler ? "status.show-more" : "status.show-less")
        }
        .buttonStyle(.bordered)
        .accessibilityHidden(true)
      }

      if !viewModel.displaySpoiler {
        HStack {
          EmojiTextApp(status.content, emojis: status.emojis, language: status.language)
            .font(.scaledBody)
            .environment(\.openURL, OpenURLAction { url in
              routerPath.handleStatus(status: status, url: url)
            })
          Spacer()
        }
        
        makeTranslateView(status: status)

        if let poll = status.poll {
          StatusPollView(poll: poll, status: status)
        }
        
        embedStatusView
  
        makeMediasView(status: status)
          .accessibilityHidden(!viewModel.isFocused)
        makeCardView(status: status)
      }
    }
  }

  @ViewBuilder
  private func accountView(status: AnyStatus) -> some View {
    HStack(alignment: .center) {
      if theme.avatarPosition == .top {
        AvatarView(url: status.account.avatar, size: .status)
      }
      VStack(alignment: .leading, spacing: 0) {
        EmojiTextApp(.init(stringValue: status.account.safeDisplayName), emojis: status.account.emojis)
          .font(.scaledSubheadline)
          .fontWeight(.semibold)
        Group {
          Text("@\(status.account.acct)") +
            Text(" ⸱ ") +
            Text(status.createdAt.formatted) +
            Text(" ⸱ ") +
            Text(Image(systemName: viewModel.status.visibility.iconName))
        }
        .font(.scaledFootnote)
        .foregroundColor(.gray)
      }
    }
  }

  private var menuButton: some View {
    Menu {
      StatusRowContextMenu(viewModel: viewModel)
    } label: {
      Image(systemName: "ellipsis")
        .frame(width: 30, height: 30)
    }
    .foregroundColor(.gray)
    .contentShape(Rectangle())
  }

  @ViewBuilder
  private func makeTranslateView(status: AnyStatus) -> some View {
    if let userLang = preferences.serverPreferences?.postLanguage,
       preferences.showTranslateButton,
       status.language != nil,
       userLang != status.language,
       !status.content.asRawText.isEmpty,
       viewModel.translation == nil
    {
      Button {
        Task {
          await viewModel.translate(userLang: userLang)
        }
      } label: {
        if viewModel.isLoadingTranslation {
          ProgressView()
        } else {
          Text("status.action.translate")
        }
      }
    }
    
    if let translation = viewModel.translation, !viewModel.isLoadingTranslation {
      GroupBox {
        VStack(alignment: .leading, spacing: 4) {
          Text(translation)
            .font(.scaledBody)
          Text("status.action.translated-label")
            .font(.footnote)
            .foregroundColor(.gray)
        }
      }
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  @ViewBuilder
  private func makeMediasView(status: AnyStatus) -> some View {
    if !status.mediaAttachments.isEmpty {
      if theme.statusDisplayStyle == .compact {
        HStack {
          StatusMediaPreviewView(attachments: status.mediaAttachments,
                                 sensitive: status.sensitive,
                                 isNotifications: viewModel.isCompact)
          Spacer()
        }
        .padding(.vertical, 4)
      } else {
        StatusMediaPreviewView(attachments: status.mediaAttachments,
                               sensitive: status.sensitive,
                               isNotifications: viewModel.isCompact)
          .padding(.vertical, 4)
      }
    }
  }

  @ViewBuilder
  private func makeCardView(status: AnyStatus) -> some View {
    if let card = status.card,
       viewModel.embeddedStatus?.url != status.card?.url,
       status.mediaAttachments.isEmpty,
       !viewModel.isEmbedLoading,
       theme.statusDisplayStyle == .large
    {
      StatusCardView(card: card)
    }
  }
  
  @ViewBuilder
  private var embedStatusView: some View {
    if !reasons.contains(.placeholder) {
      if !viewModel.isCompact, !viewModel.isEmbedLoading,
          let embed = viewModel.embeddedStatus {
        StatusEmbeddedView(status: embed)
      } else if viewModel.isEmbedLoading, !viewModel.isCompact {
        StatusEmbeddedView(status: .placeholder())
          .redacted(reason: .placeholder)
          .shimmering()
      }
    }
  }
}
