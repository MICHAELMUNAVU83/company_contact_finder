defmodule CompanyContactFinder.OutreachTest do
  use CompanyContactFinder.DataCase, async: true

  import CompanyContactFinder.LeadStubs
  import Swoosh.TestAssertions

  alias CompanyContactFinder.Leads
  alias CompanyContactFinder.Leads.Bucket
  alias CompanyContactFinder.Leads.Lookup
  alias CompanyContactFinder.Outreach
  alias CompanyContactFinder.Outreach.Message
  alias CompanyContactFinder.Repo

  setup do
    {:ok, bucket} = Leads.create_bucket(bucket_with_product())

    lookup =
      Repo.insert!(%Lookup{company_name: "Acme Logistics", bucket_id: bucket.id, status: :done})

    Leads.add_contacts(lookup, [
      %{type: :email, value: "sales@acmelogistics.co.ke", source_url: "https://acme.test"}
    ])

    Leads.save_brief(lookup, %{
      status: :done,
      pitch: "Offer barcode numbers for their freight labels",
      best_contact: "sales@acmelogistics.co.ke"
    })

    lookup = Leads.get_lookup!(lookup.id)
    bucket = Leads.get_bucket!(bucket.id)
    %{bucket: bucket, lookup: lookup}
  end

  test "preview fills the template and does not send", %{bucket: bucket, lookup: lookup} do
    [draft] = Outreach.preview(bucket, [lookup])

    assert draft.to == "sales@acmelogistics.co.ke"
    assert draft.subject == "GS1 barcodes for Acme Logistics"
    assert draft.body =~ "Offer barcode numbers"
    assert draft.body =~ "If that applies to Acme Logistics"
    refute draft.body =~ "The contact we found"
    refute draft.sent?
    assert Outreach.preview(bucket, [lookup])
    refute_email_sent()
  end

  test "firing a campaign sends once", %{bucket: bucket, lookup: lookup} do
    [draft] = Outreach.preview(bucket, [lookup])
    assert Outreach.fire(bucket, [draft]) == %{sent: 1, skipped: 0}

    assert_email_sent(
      from: {"GS1 Kenya Lead Finder", "leads@example.com"},
      to: "sales@acmelogistics.co.ke",
      subject: "GS1 barcodes for Acme Logistics",
      text_body: draft.body
    )

    assert draft.body =~ "If that applies to Acme Logistics"
    assert draft.body =~ "Reply stop if you do not want these emails."
    refute draft.body =~ "Amina, GS1 Kenya"

    message = Repo.get_by!(Message, lookup_id: lookup.id)
    assert message.body == draft.body

    [again] = Outreach.preview(bucket, [lookup])
    assert again.sent?
    assert Outreach.fire(bucket, [again]) == %{sent: 0, skipped: 1}
  end

  test "a footer is filled and sent with the bucket from address", %{
    bucket: bucket,
    lookup: lookup
  } do
    {:ok, bucket} =
      Leads.update_campaign(bucket, %{
        "email_footer" => "Amina, GS1 Kenya\n{{product}} for {{company}}",
        "from_name" => "Amina",
        "from_email" => "Amina@GS1Kenya.org"
      })

    [draft] = Outreach.preview(bucket, [lookup])

    assert draft.body =~ "Offer barcode numbers"
    assert draft.body =~ "Amina, GS1 Kenya"
    assert draft.body =~ "GS1 barcodes for Acme Logistics"
    assert draft.body =~ "Reply stop if you do not want these emails."
    assert before?(draft.body, "Offer barcode numbers", "Amina, GS1 Kenya")
    assert before?(draft.body, "Amina, GS1 Kenya", "Reply stop if you do not want these emails.")
    refute_email_sent()

    assert Outreach.fire(bucket, [draft]) == %{sent: 1, skipped: 0}

    assert_email_sent(
      from: {"Amina", "amina@gs1kenya.org"},
      to: "sales@acmelogistics.co.ke",
      text_body: draft.body
    )

    message = Repo.get_by!(Message, lookup_id: lookup.id)
    assert message.body == draft.body
  end

  test "from name and from email must be set together", %{bucket: bucket} do
    name_only = Bucket.campaign_changeset(bucket, %{"from_name" => "Amina"})
    assert "can't be blank" in errors_on(name_only).from_email

    email_only = Bucket.campaign_changeset(bucket, %{"from_email" => "amina@gs1kenya.org"})
    assert "can't be blank" in errors_on(email_only).from_name

    blank = Bucket.campaign_changeset(bucket, %{"from_name" => "", "from_email" => ""})
    assert blank.valid?

    bad =
      Bucket.campaign_changeset(bucket, %{
        "from_name" => "Amina",
        "from_email" => "not-an-email"
      })

    assert "must be an email" in errors_on(bad).from_email
  end

  test "a finished lookup does not send mail on its own", %{bucket: bucket} do
    stub_all()
    lookup = Repo.insert!(%Lookup{company_name: "Quiet Co", bucket_id: bucket.id})
    CompanyContactFinder.Leads.Pipeline.run(lookup.id)
    refute_email_sent()
  end

  defp before?(text, earlier, later) do
    {earlier_at, _} = :binary.match(text, earlier)
    {later_at, _} = :binary.match(text, later)
    earlier_at < later_at
  end
end
