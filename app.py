import streamlit as st
import pandas as pd
import plotly.express as px
import snowflake.connector

st.set_page_config(
    page_title="Vehicle Inventory Health Analytics",
    page_icon="🚗",
    layout="wide",
)


@st.cache_data(ttl=300)
def load_data():
    conn = snowflake.connector.connect(
        account=st.secrets["snowflake"]["account"],
        user=st.secrets["snowflake"]["user"],
        password=st.secrets["snowflake"]["password"],
        warehouse=st.secrets["snowflake"]["warehouse"],
        database="VEHICLE_DB",
        schema="VEHICLE_SCHEMA",
    )
    query = "SELECT * FROM VEHICLE_DB.VEHICLE_SCHEMA.INVENTORY_HEALTH"
    df = pd.read_sql(query, conn)
    conn.close()
    df.columns = df.columns.str.upper()
    return df


def main():
    st.title("Vehicle Inventory Health Analytics")
    st.markdown("Track vehicle aging and identify slow-moving inventory.")

    df = load_data()

    # --- Sidebar Filters ---
    st.sidebar.header("Filters")

    dealers = sorted(df["DEALER_ID"].unique())
    selected_dealers = st.sidebar.multiselect("Dealer", dealers, default=dealers)

    makes = sorted(df["MAKE"].unique())
    selected_makes = st.sidebar.multiselect("Make", makes, default=makes)

    models = sorted(df["MODEL"].unique())
    selected_models = st.sidebar.multiselect("Model", models, default=models)

    buckets = ["GREEN", "YELLOW", "RED"]
    selected_buckets = st.sidebar.multiselect("Aging Bucket", buckets, default=buckets)

    # Apply filters
    filtered = df[
        (df["DEALER_ID"].isin(selected_dealers))
        & (df["MAKE"].isin(selected_makes))
        & (df["MODEL"].isin(selected_models))
        & (df["AGING_CATEGORY"].isin(selected_buckets))
    ]

    # --- KPI Cards ---
    st.markdown("---")
    col1, col2, col3, col4 = st.columns(4)

    total_vehicles = len(filtered)
    avg_days = filtered["DAYS_ON_LOT"].mean() if total_vehicles > 0 else 0
    red_count = len(filtered[filtered["AGING_CATEGORY"] == "RED"])
    total_value = filtered["CURRENT_PRICE"].sum()

    col1.metric("Total Vehicles", f"{total_vehicles}")
    col2.metric("Avg Days on Lot", f"{avg_days:.1f}")
    col3.metric("Vehicles in Red", f"{red_count}")
    col4.metric("Inventory Value", f"${total_value:,.0f}")

    st.markdown("---")

    # --- Visualizations ---
    chart_col1, chart_col2 = st.columns(2)

    # 1. Inventory by Aging Bucket
    with chart_col1:
        st.subheader("Inventory by Aging Bucket")
        bucket_counts = (
            filtered.groupby("AGING_CATEGORY")
            .size()
            .reset_index(name="COUNT")
        )
        color_map = {"GREEN": "#2ecc71", "YELLOW": "#f1c40f", "RED": "#e74c3c"}
        fig1 = px.bar(
            bucket_counts,
            x="AGING_CATEGORY",
            y="COUNT",
            color="AGING_CATEGORY",
            color_discrete_map=color_map,
            category_orders={"AGING_CATEGORY": ["GREEN", "YELLOW", "RED"]},
        )
        fig1.update_layout(showlegend=False, xaxis_title="Aging Bucket", yaxis_title="Count")
        st.plotly_chart(fig1, use_container_width=True)

    # 2. Inventory by Make
    with chart_col2:
        st.subheader("Inventory by Make")
        make_counts = (
            filtered.groupby("MAKE")
            .size()
            .reset_index(name="COUNT")
            .sort_values("COUNT", ascending=True)
        )
        fig2 = px.bar(
            make_counts,
            x="COUNT",
            y="MAKE",
            orientation="h",
            color_discrete_sequence=["#3498db"],
        )
        fig2.update_layout(xaxis_title="Count", yaxis_title="")
        st.plotly_chart(fig2, use_container_width=True)

    chart_col3, chart_col4 = st.columns(2)

    # 3. Inventory by Dealer
    with chart_col3:
        st.subheader("Inventory by Dealer")
        dealer_counts = (
            filtered.groupby("DEALER_ID")
            .size()
            .reset_index(name="COUNT")
        )
        dealer_counts["DEALER_ID"] = dealer_counts["DEALER_ID"].astype(str)
        fig3 = px.pie(
            dealer_counts,
            values="COUNT",
            names="DEALER_ID",
            hole=0.4,
            color_discrete_sequence=px.colors.qualitative.Set2,
        )
        fig3.update_layout(legend_title_text="Dealer ID")
        st.plotly_chart(fig3, use_container_width=True)

    # 4. Top 10 Oldest Vehicles
    with chart_col4:
        st.subheader("Top 10 Oldest Vehicles")
        top10 = filtered.nlargest(10, "DAYS_ON_LOT")[
            ["MAKE", "MODEL", "DAYS_ON_LOT", "AGING_CATEGORY"]
        ].copy()
        top10["LABEL"] = top10["MAKE"] + " " + top10["MODEL"]
        fig4 = px.bar(
            top10,
            x="DAYS_ON_LOT",
            y="LABEL",
            orientation="h",
            color="AGING_CATEGORY",
            color_discrete_map=color_map,
            category_orders={"AGING_CATEGORY": ["GREEN", "YELLOW", "RED"]},
        )
        fig4.update_layout(
            xaxis_title="Days on Lot",
            yaxis_title="",
            yaxis={"categoryorder": "total ascending"},
            showlegend=False,
        )
        st.plotly_chart(fig4, use_container_width=True)

    # --- Data Table ---
    st.markdown("---")
    st.subheader("Filtered Inventory Data")
    st.dataframe(
        filtered[
            ["VEHICLE_ID", "VIN", "MAKE", "MODEL", "DEALER_ID", "DAYS_ON_LOT",
             "AGING_CATEGORY", "CURRENT_PRICE", "STATUS"]
        ].sort_values("DAYS_ON_LOT", ascending=False),
        use_container_width=True,
        hide_index=True,
    )


if __name__ == "__main__":
    main()
