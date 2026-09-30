#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"
#include <linux/limits.h>
#include <unistd.h>

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  guint show_window_timeout_id;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Shows the window only once Flutter has produced its first frame. Showing it
// earlier (as the stock template does) leaves the user staring at a black,
// empty window for the whole engine/theme startup, and permanently so if no
// frame is ever produced.
static void my_application_first_frame_cb(MyApplication* self, FlView* view) {
  if (self->show_window_timeout_id != 0) {
    g_source_remove(self->show_window_timeout_id);
    self->show_window_timeout_id = 0;
  }
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Safety net for the deferred show above: if Flutter never delivers a first
// frame (an error before runApp, an engine failure), the window would stay
// hidden forever and the app would be invisible and impossible to close. Show
// it anyway after a short grace period so the failure is visible.
static gboolean my_application_show_window_timeout(gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  self->show_window_timeout_id = 0;
  GtkWindow* window = gtk_application_get_active_window(GTK_APPLICATION(self));
  if (window != nullptr) {
    gtk_widget_show(GTK_WIDGET(window));
  }
  return G_SOURCE_REMOVE;
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  char self_path[PATH_MAX];
  ssize_t count = readlink("/proc/self/exe", self_path, PATH_MAX);
  if (count != -1) {
    char* path_end = strrchr(self_path, '/');
    if (path_end != nullptr) {
      *path_end = '\0';
    }
    g_autofree gchar* icon_path = g_build_filename(self_path, "data", "assets", "app_icon.svg", nullptr);
    if (g_file_test(icon_path, G_FILE_TEST_EXISTS)) {
        gtk_window_set_icon_from_file(window, icon_path, nullptr);
    }
  }

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "autononext");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "autononext");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  // Defer showing the window until the first frame is rendered.
  g_signal_connect_swapped(view, "first-frame",
                           G_CALLBACK(my_application_first_frame_cb), self);

  // ...but never leave the user with no window at all if no frame arrives.
  self->show_window_timeout_id =
      g_timeout_add_seconds(5, my_application_show_window_timeout, self);

  gtk_widget_realize(GTK_WIDGET(view));
  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  if (self->show_window_timeout_id != 0) {
    g_source_remove(self->show_window_timeout_id);
    self->show_window_timeout_id = 0;
  }
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
